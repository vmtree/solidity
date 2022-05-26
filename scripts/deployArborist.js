const { ethers } = require('hardhat');

async function main() {
    const linkPayment = ethers.utils.parseUnits('0.1', 18);
    const rinkebyLink = "0x01BE23585060835E02B77ef475b0Cc51aA1e0709";
    const factory = await ethers.getContractFactory('Arborist');
    const arborist = await factory.deploy(
        linkPayment,
        rinkebyLink,
        "0x0badc0de0badc0de0badc0de0badc0de00000000000000000000000000000000"
    );
    console.log(arborist.address);
};

main().then(() => process.exit());