const hre = require("hardhat")

async function main(){
    const opAddress = "0x32dFFB704CBaBe9298223C04D4aCa7a3963b992a"
    const mockapp = await hre.ethers.getContractAt("AppV1", opAddress)

    const owner = await mockapp.owner()
    console.log("owner : ", owner)

    const encoder = new TextEncoder();

    const message = "mock packet data"
    const bytesMessage = encoder.encode(message)
    
    console.log({bytesMessage})

    // await mockapp.sendPacket(bytesMessage, "mockapp", "channel-1", { revision_number: 1, revision_height: 100000 }, 1000000);
    const tx = await mockapp.sendPacket(bytesMessage, "mockapp", "channel-1", { revision_number: 0, revision_height: 24036180 }, 0, {gasLimit: 500000});    //optimism
    console.log({tx});

    // console.log({owner});
}

main()