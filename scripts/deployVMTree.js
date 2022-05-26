const { ethers } = require('hardhat');

function encodeDeploy(controller, name) {
    return ethers.utils.defaultAbiCoder.encode(
        ["address", "string"], [controller, name]
    );
}

async function main() {
    const rinkebyLink = "0x01BE23585060835E02B77ef475b0Cc51aA1e0709";
    const linkFactory = await ethers.getContractFactory('LinkToken');
    const signer = await ethers.getSigner();
    const linkToken = new ethers.Contract(
        rinkebyLink, linkFactory.interface, signer
    );

    const arborist = "0xdd07fB4b59083d26F216f35CCDb18866E98e9762";
    const linkAmount = ethers.utils.parseUnits('1', 18);

    const tx = await linkToken.transferAndCall(
        arborist, linkAmount, encodeDeploy(signer.address, "VMTree")
    );
    const receipt = await tx.wait();
    const arboristFactory = await ethers.getContractFactory('Arborist');
    console.log(arboristFactory.interface.parseLog(receipt.logs[2]));
};

main().then(() => process.exit());