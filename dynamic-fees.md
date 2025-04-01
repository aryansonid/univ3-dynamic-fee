# Dynamic Fees Implementation

Uniswap V3 introduces dynamic fees to adjust trading fees based on market volatility. Instead of a fixed fee, the protocol calculates fees dynamically based on recent price movements. This helps mitigate impermanent loss and improves efficiency.

## How Dynamic Fees Work

Observation Window: The contract observes the price 10 minutes ago and the current price.

Volatility Calculation: The price difference percentage is computed.

Fee Adjustment: Based on the volatility, the trading fee is adjusted dynamically.

## Key Functions

getFee(int24 currentTick): Returns the applicable trading fee, either fixed or dynamic.

getDynamicFee(int24 currentTick): Computes the dynamic fee based on historical price changes.

observe(uint32[] calldata secondsAgos): Fetches the price history at given time intervals.

## Running Foundry Tests

This project supports testing with Foundry in addition to Hardhat. To run Foundry tests:

- Ensure Foundry is installed:
  ```
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```

- Install dependecies

  ```
  git submodule update --init --recursive
  ```

  or you can manually install dependencies

  ```
  forge install OpenZeppelin/openzeppelin-contracts@v3.4.0

  forge install foundry-rs/forge-std

  ```
- Run test:
  ```
  forge test
  ```
