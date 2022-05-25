const { ethers } = require('hardhat');
const { utils } = require('vmtjs');
const { unsafeRandomLeaves } = utils;

function hexPadLeft(h) {
    return '0x' + h.slice(2).padStart(64, '0');
}

async function main() {
    const vmtreeAddress = "0x68FAb397179Ad560980995Ca45aE9Ea064501d10";
    const treeFactory = await ethers.getContractFactory("VMTree");
    const signer = await ethers.getSigner();
    const vmtree = new ethers.Contract(
        vmtreeAddress, treeFactory.interface, signer
    );
    const leaves = unsafeRandomLeaves(1);

    for (let i = 0; i < leaves.length; i++) {
        await vmtree.commit(leaves[i]);    
    }
};

main().then(() => process.exit());