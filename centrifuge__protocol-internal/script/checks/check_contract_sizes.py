#!/usr/bin/env python3
"""
Checks every contract declared under src/ against the code size limit of the chains it has to deploy on.

That is EIP-170 (24,576 bytes of runtime code) and EIP-3860 (49,152 bytes of init code) for everything,
because the protocol launches on chains that enforce them. The exceptions are the contracts in
`EIP_7907_CONTRACTS`, which only deploy where EIP-7907 is active and are held to its limits instead (65,536
and 131,072): a launch deploys them only on a chain whose config sets `.network.vaults`.

Sizes come from `forge build --sizes --json` under the profile in use, which is the bytecode a deployment
ships. Forge exits non-zero on its own EIP-170 check whenever an exception is over it, so its exit status
is ignored and its JSON is the input; a build that produced none fails here instead.

The report keys a contract by its bare name, unless the build holds two contracts of that name, in which
case every one of them is keyed `Name (path)`. A src/ contract is looked up under its path first, so one
whose name a test or script contract shares is still checked, and a src/ contract missing from the report
under either key fails the check rather than dropping out of it. Libraries are the exception: one with only
internal functions has no bytecode of its own and is absent from the report by design.

    python3 script/checks/check_contract_sizes.py              # runs forge itself
    python3 script/checks/check_contract_sizes.py sizes.json   # reads a `forge build --sizes --json` output
    python3 script/checks/check_contract_sizes.py --self-test  # runs the checker against fixtures
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

EIP_170_RUNTIME = 24_576
EIP_3860_INITCODE = 49_152
EIP_7907_RUNTIME = 65_536
EIP_7907_INITCODE = 131_072

# Over EIP-170 by design, and deployed only on chains with EIP-7907 (see src/vaults/ARCHITECTURE.md). Adding a name
# here takes a contract off the EIP-170 gate for good, so it should come with the same opt-in the vaults have
EIP_7907_CONTRACTS = {
    "Vault": "a vault is one flat contract over EIP-170",
    "VaultFactory": "carries the vault's creation code",
}

DECLARATION = re.compile(r"^\s*(contract|library)\s+(\w+)", re.MULTILINE)


def declared_contracts(root: Path) -> list:
    """Every (kind, name, path) declared under src/, the path relative to the root as forge reports it."""
    declared = []
    for path in sorted((root / "src").rglob("*.sol")):
        for kind, name in DECLARATION.findall(path.read_text()):
            declared.append((kind, name, path.relative_to(root).as_posix()))
    return declared


def resolve(sizes: dict, name: str, path: str):
    """The report entry of one src/ contract: under its path when the name is shared, else bare."""
    return sizes.get(f"{name} ({path})", sizes.get(name))


def forge_sizes(root: Path) -> str:
    forge = os.environ.get("FORGE", "forge")
    result = subprocess.run(
        [forge, "build", "--sizes", "--json"], cwd=root, capture_output=True, text=True, check=False
    )
    return result.stdout


def check(root: Path, raw: str) -> int:
    try:
        sizes = json.loads(raw)
    except json.JSONDecodeError:
        print("Error: no size report to read; did `forge build --sizes --json` compile?")
        return 1

    failures = []
    measured = {}

    for kind, name, path in declared_contracts(root):
        size = resolve(sizes, name, path)
        if size is None:
            if kind == "contract":
                failures.append(f"{name} ({path}): declared under src/ but not in the size report")
            continue
        measured[name] = size

    for name in sorted(EIP_7907_CONTRACTS):
        if name not in measured:
            failures.append(f"{name}: listed in EIP_7907_CONTRACTS but not in the size report")
        elif measured[name]["runtime_size"] <= EIP_170_RUNTIME:
            failures.append(
                f"{name}: fits EIP-170 again ({measured[name]['runtime_size']:,} bytes), drop it from EIP_7907_CONTRACTS"
            )

    for name, size in sorted(measured.items()):
        exempt = name in EIP_7907_CONTRACTS
        runtime_limit, init_limit = (
            (EIP_7907_RUNTIME, EIP_7907_INITCODE) if exempt else (EIP_170_RUNTIME, EIP_3860_INITCODE)
        )
        label = "EIP-7907" if exempt else "EIP-170/EIP-3860"

        if size["runtime_size"] > runtime_limit:
            failures.append(f"{name}: {size['runtime_size']:,} bytes of runtime code, over {label} ({runtime_limit:,})")
        if size["init_size"] > init_limit:
            failures.append(f"{name}: {size['init_size']:,} bytes of init code, over {label} ({init_limit:,})")

    for name in sorted(EIP_7907_CONTRACTS):
        if name in measured:
            print(f"{name}: {measured[name]['runtime_size']:,} bytes, held to EIP-7907 ({EIP_7907_CONTRACTS[name]})")

    if failures:
        print("\nError: contracts over the size limit of the chains they deploy on, or not measured at all:")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print(f"Every other src/ contract fits EIP-170 ({EIP_170_RUNTIME:,}) and EIP-3860 ({EIP_3860_INITCODE:,})")
    return 0


def self_test() -> int:
    """Runs the checker against fixtures: a src/ contract keyed by path because a test contract shares its
    name, over the limit, has to fail the check; one missing from the report has to fail it; an all-internal
    library missing from it does not."""
    small = {"runtime_size": 100, "init_size": 200}
    large = {"runtime_size": EIP_170_RUNTIME + 1, "init_size": 200}
    vaults = {
        "Vault": {"runtime_size": 30_000, "init_size": 31_000},
        "VaultFactory": {"runtime_size": 40_000, "init_size": 41_000},
    }
    cases = [
        ("a src/ contract keyed by path", {"Shared (src/Shared.sol)": large, "Shared (test/Shared.t.sol)": small}, 1),
        ("the same contract within the limit", {"Shared (src/Shared.sol)": small, "Shared (test/Shared.t.sol)": large}, 0),
        ("a src/ contract keyed by bare name", {"Shared": large}, 1),
        ("a src/ contract missing from the report", {"Other": small}, 1),
    ]

    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src").mkdir()
        (root / "src" / "Shared.sol").write_text("contract Shared {}\nlibrary Internal {}\n")
        (root / "src" / "Vault.sol").write_text("contract Vault {}\ncontract VaultFactory {}\n")

        for label, report, expected in cases:
            print(f"--- {label}")
            if check(root, json.dumps({**vaults, **report})) != expected:
                failed.append(label)

    if failed:
        print(f"\nError: the checker misjudged: {', '.join(failed)}")
        return 1
    print("\nThe checker judged every fixture as expected")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()

    root = Path(__file__).resolve().parents[2]
    raw = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else forge_sizes(root)
    return check(root, raw)


if __name__ == "__main__":
    sys.exit(main())
