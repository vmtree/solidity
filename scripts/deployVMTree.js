const { ethers } = require('hardhat');

function hexPadLeft(h) {
    return '0x' + h.slice(2).padStart(64, '0');
}

async function main() {
    const rinkebyLink = "0x01BE23585060835E02B77ef475b0Cc51aA1e0709";
    const linkFactory = await ethers.getContractFactory('LinkToken');
    const signer = await ethers.getSigner();
    const linkToken = new ethers.Contract(
        rinkebyLink, linkFactory.interface, signer
    );

    const arborist = "0x0123FC63Aa73bD37739337973B5e13cdCf4FD8f8";
    const linkAmount = ethers.utils.parseUnits('1', 18);

    const tx = await linkToken.transferAndCall(
        arborist, linkAmount, hexPadLeft(signer.address)
    );
    const receipt = await tx.wait();
    console.log(receipt);
};

main().then(() => process.exit());