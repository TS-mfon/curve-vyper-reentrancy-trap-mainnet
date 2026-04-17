# Curve Vyper Reentrancy Trap (mainnet)

This repository is part of Operation Flytrap. It is a Drosera-compatible executable PoC for a historical exploit mechanic.

## Drosera MCP Inputs

- `generate-trap` prompt for `CURVE_ACCOUNTED_BALANCE_MISMATCH`
- `drosera://trappers/creating-a-trap`
- `drosera://trappers/dryrunning-a-trap`
- `drosera://trappers/drosera-cli`
- `drosera://operators/executing-traps`
- `drosera://deployments`

## Scope

This repo uses Drosera MCP rules for trap structure:

- `collect()` is `external view`.
- `shouldRespond(bytes[] calldata data)` is `external pure`.
- samples are newest-first.
- `block_sample_size = 5`.
- response payload is ABI-encoded `TrapAlert`.

## Invariant

`CURVE_ACCOUNTED_BALANCE_MISMATCH`

The response contains the invariant id, target, observed value, expected value, block number, and ABI-encoded context.

## Exploit Mechanic

The Hoodi version deploys all protocol mocks and tokens needed to simulate the exploit. The mainnet version contains production-oriented trap and response contracts with placeholder target addresses until authorized mainnet addresses are supplied.

For this trap, the simulated response is: pause swaps and liquidity removal.

## Run Tests

```bash
forge test
```

## Hoodi Notes

This mainnet repo does not deploy mocks. It uses synthetic windows for deterministic tests until real target addresses are supplied.
