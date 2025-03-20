const hre = require("hardhat")

async function main(){
    const userAddr = "0x3DdbD20EF02D8aD4eB748F5416A81BA7B19E58A7"
    const tokenAddr = "0x8030129c54F95293fC0CfCEAB7821Cd91dFd5573";
    const ics20TransferAddr = "0x9fE7F62A48fb6a389e09eB3AB3AB664988BFc0b9"
    const ics20Transfer = await hre.ethers.getContractAt("ICS20Transfer", ics20TransferAddr);
    const tokenContract = await hre.ethers.getContractAt("ERC20", tokenAddr);

    console.log("balance of ics20 contract : ", await tokenContract.balanceOf(ics20TransferAddr));

    console.log("balance : ", await tokenContract.balanceOf(userAddr));

    console.log("before : ", await ics20Transfer.balanceOf(userAddr, tokenAddr.toString()));
    
    //############### deposit ################
    const amount = hre.ethers.parseEther("2")
    // await tokenContract.approve(ics20TransferAddr, amount);

    try {
        await ics20Transfer.deposit(userAddr, tokenAddr, amount);
    } catch (error) {
        console.log("error : ", error);
    }
    // console.log("after : ", await ics20Transfer.balanceOf(userAddr, tokenAddr.toString()));
}

main()