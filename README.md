# Contracts • Shipchain | Chainlink Hackathon Spring 2023
## Content
There are three main contracts in this repository:
- Shipping → It handles the process of sending any kind of package in the real world. It gathers location data from IoT devices and stores it in the blockchain.
- Order → stores the status of shipping orders
- ConvertLatLng → a helper used to validate serialization/deserialization of `LatLng` data as `int256`.

Throughout the hackathon, we have studied three different main approaches when developing our Shipping contract, each one based on different Chainlink services:

- Shipping → Implementation using external Chainlink API calls
- ShippingFunctionsConsumer → Implementation using the Chainlink Functions framework
- ShippingAutomatedFunctionsConsumer → Implementation using Chainlink functions and the automate framework

Finally, we decided to go ahead with the API Consumer option due to the simplicity of its implementation, which is extremely practical. The lack of reasons to automate some of the contract callbacks also led us to that decision. Currently, all functions in the contracts are triggered based on user input/interaction via the Web Dashboard. The delivery contract is responsible for handling all such requests, which can change contract state variables, read data from sources outside the chain, create new order contracts, and update order states.


## How to run tests and deploy the Oracle Contract implementation?
1. After cloning this repository in your machine, you should run `npm install` from the repo root folder to install all the required packages.

2. After downloading the packages, don't forget to initialize the environment variables! Use `env-enc` package for that. In the command line, enter: `npx env-env set-pw`. After setting an encryption password you can easily remember, add the environment variables also using the CLI (`npx env-enc set`) according to the [.env_sample](./.env_sample) specs.

3. Then, you can run unit tests locally using the commands `npm run test` or `npm run test:unit` or even `hardhat test test/unit/*.spec.js`. These commands tests the Shipping functions directly involved to oracles integration.

4. To deploy and auto fund the contract on default network, use `npm run deploy` or `hardhat run scripts/deployment/main.js`.

5. You can also specify the target network by running, for instance, `hardhat run scripts/deployment/main.js --network ethereumSepolia`.

## How to interact with the Contracts?
For that, you can use either [Remix IDE](https://remix.ethereum.org/) or any client for EVM contracts, such as [ethers](https://docs.ethers.org/v5/) or [web3js](https://web3js.readthedocs.io/en/v1.10.0/) libraries for JavaScript. We strongly recommend you to interact with the contract using the Web front-end we've designed during the hackathon. Its source code is available at [GitHub](https://github.com/GuilhermePC09/Backoffice-ChainlinkSpringHack23).


## Learn more
All the Oracle contracts were created based mostly on [Chainlink Docs](https://docs.chain.link/) and on their two public demo repositories:
- [smartcontractkit/hardhat-starter-kit](https://github.com/smartcontractkit/hardhat-starter-kit)
- [smartcontractkit/functions-hardhat-starter-kit](https://github.com/smartcontractkit/functions-hardhat-starter-kit)

These repos were extremely useful to get in touch with all the concepts behind hardhat framework, besides of allowing us to notice its deep&seamless integration with Chainlink. It was very powerful and grateful to create contracts, test them locally, deploy to any target network we'd like using scripts, fund Chainlink functions, etc. All of that was possible due to that public examples.