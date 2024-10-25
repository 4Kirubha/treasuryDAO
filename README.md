# TreasuryDAO Contract

This repository contains the `TreasuryDAO` smart contract, which allows users to schedule cross-chain token transfers with support for relayer fees and multi-signature approvals.

## Overview

The `TreasuryDAO` contract enables users to create intents for transferring tokens across different chains. Users can schedule or modify intents, and the contract supports both native tokens and ERC20 tokens.

## Testing with Foundry

### Prerequisites

Ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/)
- [Node.js](https://nodejs.org/) (for any additional scripts)

### Running Tests

To run the tests, navigate to the project directory and execute:

```bash
forge test --fork-url RPC_URL --evm-version cancun
