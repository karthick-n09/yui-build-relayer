function saveAddress(contractName, contract) {
  const fs = require("fs");
  const path = require("path");

  const dirpath = path.join("addresses", network.config.chainId.toString());
  if (!fs.existsSync(dirpath)) {
    fs.mkdirSync(dirpath, {recursive: true});
  }

  const filepath = path.join(dirpath, contractName);
  fs.writeFileSync(filepath, contract.target);

  console.log(`${contractName} address:`, contract.target);
}

async function deploy(deployer, contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.connect(deployer).deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

async function deployIBC(deployer) {
  const logicNames = [
    "IBCClient",
    "IBCConnectionSelfStateNoValidation",
    "IBCChannelHandshake",
    "IBCChannelPacketSendRecv",
    "IBCChannelPacketTimeout",
    "IBCChannelUpgradeInitTryAck",
    "IBCChannelUpgradeConfirmOpenTimeoutCancel",
  ];
  const logics = [];
  for (const name of logicNames) {
    const logic = await deploy(deployer, name);
    logics.push(logic);
  }
  return deploy(deployer, "OwnableIBCHandler", logics.map(l => l.target));
}

async function deployProxy(deployer, contractName, constructorArgs, unsafeAllow, initializer, initialArgs) {
  const factory = await hre.ethers.getContractFactory(contractName).then(f => f.connect(deployer));
  const proxyOptions /* : DeployProxyOptions */ = {
    txOverrides: {},
    unsafeAllow: unsafeAllow ?? [],
    constructorArgs,
    initializer: initializer ?? false,
    redeployImplementation: 'always'
  };
  const proxyContract = await upgrades.deployProxy(
    factory,
    initialArgs ?? [],
    proxyOptions
  );
  await proxyContract.waitForDeployment();
  return proxyContract.connect(deployer);
}

async function prepareImplementation(deployer, proxy, contractName, constructorArgs, unsafeAllow) {
  const factory = await hre.ethers.getContractFactory(contractName).then(f => f.connect(deployer));
  const implOptions /* : DeployImplementationOptions */ = {
    constructorArgs,
    txOverrides: {},
    unsafeAllow: unsafeAllow ?? [],
    redeployImplementation: 'always',
    getTxResponse: true
  };
  const tx = await hre.upgrades.prepareUpgrade(proxy, factory, implOptions);
  const receipt = await tx.wait(3);
  const implContract = await hre.ethers.getContractAt(contractName, receipt.contractAddress);
  return implContract.connect(deployer);
}

async function deployApp(deployer, ibcHandler) {
  //  const txOverrides = { unsafeAllow: ["constructor"] };
  const unsafeAllow = [
    "constructor", // IBCChannelUpgradableMockApp, IBCMockApp, Ownable
    "state-variable-immutable", // ibcHandler
    "state-variable-assignment", //closeChannelAllowed
  ];
  const proxyV1 = await deployProxy(deployer, "AppV1", [ibcHandler.target], unsafeAllow, "__AppV1_init(string)", ["mockapp-1"]);
  saveAddress("AppV1", proxyV1);

  for (let i = 2; i <= 10; i++) {
    const contractName = `AppV${i}`;
    const impl = await prepareImplementation(deployer, proxyV1, contractName, [ibcHandler.target], unsafeAllow);
    saveAddress(contractName, impl);

    await proxyV1.proposeAppVersion(
      `mockapp-${i}`,
      impl.target,
      impl.interface.encodeFunctionData(`__${contractName}_init(string)`, [contractName]),
    ).then(tx => tx.wait());
  }

  return proxyV1;
}

async function main() {
  // This is just a convenience check
  if (network.name === "hardhat") {
    console.warn(
      "You are trying to deploy a contract to the Hardhat Network, which" +
        "gets automatically created and destroyed every time. Use the Hardhat" +
        " option '--network localhost'"
    );
  }

  // ethers is available in the global scope
  const [deployer] = await hre.ethers.getSigners();
  console.log(
    "Deploying the contracts with the account:",
    await deployer.getAddress()
  );
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.getAddress())).toString());

  const ibcHandler = await deployIBC(deployer);
  saveAddress("IBCHandler", ibcHandler);

  const erc20token = await deploy(deployer, "ERC20Token", ["simple", "simple", 1000000]);
  saveAddress("ERC20Token", erc20token);

  const ics20transfer = await deploy(deployer, "ICS20Transfer", [ibcHandler.target, "transfer"]);
  saveAddress("ICS20Transfer", ics20transfer);

  console.log("test : before");
  const app = await deployApp(deployer, ibcHandler);
  console.log("test : after");

  const mockClient = await deploy(deployer, "MockClient", [ibcHandler.target]);
  saveAddress("MockClient", mockClient);

  const multicall3 = await deploy(deployer, "Multicall3", []);
  saveAddress("Multicall3", multicall3);

  await ibcHandler.bindPort("transfer", ics20transfer.target);
  await ibcHandler.bindPort("mockapp", app.target);
  await ibcHandler.registerClient("mock-client", mockClient.target);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}
