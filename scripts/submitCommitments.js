const { ethers } = require('hardhat');
const { utils } = require('vmtjs');
const { unsafeRandomLeaves } = utils;

function hexPadLeft(h) {
    return '0x' + h.slice(2).padStart(64, '0');
}

async function main() {
    const vmtreeAddress = "0xdD732E916deF2744Eee604Ad067Ec8F1cCC06386";
    const treeFactory = await ethers.getContractFactory("VMTree");
    const signer = await ethers.getSigner();
    const vmtree = new ethers.Contract(
        vmtreeAddress, treeFactory.interface, signer
    );
    const leaves = unsafeRandomLeaves(1);

    for (let i = 0; i < leaves.length; i++) {
        console.log(i);
        const tx = await vmtree.commit(leaves[i]);
        console.log(tx.hash);
    }
};

main().then(() => process.exit());