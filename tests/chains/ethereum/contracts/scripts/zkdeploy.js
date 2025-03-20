const hre = require("hardhat")
const {Delpoyer, Deployer} = require("@matterlabs/hardhat-zksync-deploy");

async function main(){
    // const ibcclient = await hre.ethers.deployContract("IBCClient")
    // await ibcclient.waitForDeployment();

    // console.log("contract deployed at : ", ibcclient.target);

    
    const wallet = new hre.deployer.getWallet("e765b53056fac590db941b6192ee484503e965330222ca972ba44f107e57f1f5")
    const deployer = new Deployer(hre, wallet)
    
    const artifact = await deployer.loadArtifact("IBCClient")

    const ibcclient = await deployer.deploy(artifact, [])
    console.log("ibcclient deployed at : ", await ibcclient.getAddress())
}

main()