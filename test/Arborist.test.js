const { ethers } = require('hardhat');
const { expect } = require('chai');
const { deploy } = require('../scripts/hardhat.utils.js');
const {
    calculateSubtrees,
    calculateUpdateProof,
    calculateMassUpdateProof,
    mimcSponge,
    utils,
    verify
} = require('vmtjs');

const {
    unsafeRandomLeaves,
    toVmtUpdateSolidityInput,
    toVmtMassUpdateSolidityInput,
} = utils;


describe('[START] - Arborist.test.js', function() {
    before(async () => {
        this.signer = await ethers.getSigner();
        this.linkToken = await deploy("LinkToken");
        this.arborist = await deploy(
            "Arborist",
            [this.signer.address, this.linkToken.address]
        );
    });

    it('signer balance should be total supply', async () => {
        expect(await this.linkToken.balanceOf(this.signer.address))
            .to.be.equal(await this.linkToken.totalSupply());       
    });
});