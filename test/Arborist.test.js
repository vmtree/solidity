const { ethers } = require('hardhat');
const { expect } = require('chai');
const { deploy } = require('../scripts/hardhat.utils.js');
const { stringifyBigInts } = require('ffjavascript').utils;
const {
    calculateNextRoot,
    generateProof,
    verifyProof,
    poseidon: hasher,
    utils
} = require('vmtree-sdk');

const { unsafeRandomLeaves, flattenProof } = utils;

const wasmFileName = './circuits/mass_update.wasm';
const zkeyFileName =  './circuits/mass_update.zkey';
const verifierJson = require('../circuits/mass_update_verifier.json');

function encodeDeploy(controller, name) {
    return ethers.utils.defaultAbiCoder.encode(
        ["address", "string"], [controller, name]
    );
}

describe('[START] - Arborist.test.js', function() {
    before(async () => {
        // test accounts
        const signers = await ethers.getSigners();
        this.sergey = signers[0];
        this.linkPayer = signers[1];
        this.linkNode = signers[2];
        this.controller = signers[4];
        this.externalAccount = signers[5];

        // contract params
        this.linkPayment = ethers.utils.parseUnits('0.1');
        this.specId = "0x" + "".padStart(32, '0').padStart(64, "0badc0de");

        // commitments
        const leaves = unsafeRandomLeaves(16).map(bn => bn.toString());
        this.leaves = leaves;

        // before any commitments
        const {filledSubtrees: startSubtrees} = calculateNextRoot({hasher});
        this.startSubtrees = startSubtrees;

        // after 16 commitments
        const {root: newRoot, filledSubtrees: endSubtrees} = calculateNextRoot({
            hasher, leaves
        });
        this.newRoot = newRoot;
        this.endSubtrees = endSubtrees;

        // deploy contracts
        this.linkToken = await deploy("LinkToken");
        this.arborist = await deploy("Arborist", [
            this.linkPayment,
            this.linkToken.address,
            this.specId
        ]);
    });

    it('linkPayer balance should be 10 * linkPayment', async () => {
        await this.linkToken.connect(this.sergey).transfer(
            this.linkPayer.address,
            this.linkPayment.mul(10)
        );

        expect(await this.linkToken.balanceOf(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(10));
    });

    it('should deploy a vmtree using LINKs transferAndCall', async () => {
        const tx = await this.linkToken.connect(this.linkPayer).transferAndCall(
            this.arborist.address,
            this.linkPayment.mul(10),
            encodeDeploy(this.controller.address, "EOA VMTree")
        );
        const receipt = await tx.wait();
        const parsedLog = this.arborist.interface.parseLog(receipt.logs[2])
        const vmTreeFactory = await ethers.getContractFactory('VMTree');
        this.vmtree = new ethers.Contract(
            parsedLog.args.tree, vmTreeFactory.interface, this.controller
        );
    });

    it('should deposit 15 leaves into the tree', async () => {
        for (let i = 0; i < 15; i++) {
            await this.vmtree.commit(this.leaves[i]);
        }
    });

    it('should emit `OracleRequest` on 16th deposit', async () => {
        await expect(this.vmtree.commit(this.leaves[15]))
            .to.emit(this.arborist, 'OracleRequest')
            .withArgs(
                this.specId,
                this.vmtree.address,
                ethers.utils.solidityKeccak256(
                    ["address", "uint256"], [this.vmtree.address, "0"]
                ),
                this.linkPayment,
                this.vmtree.address,
                "0xeedd2da7", // checkMassUpdate()
                0, // cancelExpiration is always zero
                1, // dataVersion (I just saw this in the default contracts)
                "0x"
            );
    });

    it('should generate a zero knowledge proof for 16 leaves', async() => {
        const input = stringifyBigInts({
            newRoot: this.newRoot,
            startIndex: 0,
            startSubtrees: this.startSubtrees,
            endSubtrees: this.endSubtrees,
            leaves: this.leaves,
        });

        console.time('mass update proof');
        this.massUpdateProof = await generateProof({input, wasmFileName, zkeyFileName});
        console.timeEnd('mass update proof');
        const result = await verifyProof({
            proof: this.massUpdateProof.proof,
            publicSignals: this.massUpdateProof.publicSignals,
            verifierJson
        });
        expect(result).to.be.true;
    });

    it('should have correct link balances before performMassUpdate', async () => {
        expect(await this.arborist.linkPayerBalance(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(10));

        expect(await this.arborist.linkNodeBalance(this.linkNode.address))
            .to.be.equal(0);
    });

    it('should update the VMTree for 16 deposits', async () => {
        const { proof } = this.massUpdateProof;
        const p = flattenProof(proof);

        await expect(this.vmtree.connect(this.linkNode).performMassUpdate(
            this.newRoot,
            this.endSubtrees,
            p
        )).to.emit(this.arborist, 'VMTreeHarvested').withArgs(
            this.vmtree.address,
            this.linkNode.address,
            this.linkPayer.address,
            this.linkPayment
        );
    });

    it('should have correct link balances after performMassUpdate', async () => {
        expect(await this.arborist.linkPayerBalance(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(9));

        expect(await this.arborist.linkNodeBalance(this.linkNode.address))
            .to.be.equal(this.linkPayment);
    });

    it('should allow linkNode to withdraw payment', async () => {
        expect(await this.linkToken.balanceOf(this.arborist.address))
            .to.be.equal(this.linkPayment.mul(10));

        await expect(this.arborist.connect(this.linkNode).collectLinkNodeLink(
            this.linkNode.address
        )).to.emit(this.arborist, 'LinkCollected').withArgs(
            this.arborist.address,
            this.linkNode.address,
            this.linkPayment
        );

        expect(await this.linkToken.balanceOf(this.linkNode.address))
            .to.be.equal(this.linkPayment);
        expect(await this.linkToken.balanceOf(this.arborist.address))
            .to.be.equal(this.linkPayment.mul(9));
    });

    it('should deposit more commitments', async () => {
        const leaves = unsafeRandomLeaves(16);
        for (let i = 0; i < 16; i++) {
            await this.vmtree.commit(leaves[i]);
        }
    });

    it('should allow linkPayer to remove tokens', async() => {
        await expect(this.arborist.connect(this.linkPayer).collectLinkPayerLink(
            this.externalAccount.address, this.linkPayment.mul(9)
        )).to.emit(this.arborist, 'LinkCollected').withArgs(
            this.linkPayer.address,
            this.externalAccount.address,
            this.linkPayment.mul(9)
        );
    });

    it('should revert on checkMassUpdate() due to low link balance', async () => {
        await expect(this.vmtree.checkMassUpdate()).to.be.revertedWith(
            'InsufficientLinkBalance'
        );
    });

    it('should allow externalAccount to topUp tokens for linkPayer', async () => {
        await this.linkToken.connect(this.externalAccount).approve(
            this.arborist.address, this.linkPayment.mul(9)
        );

        await expect(this.arborist.connect(this.externalAccount).topUpLink(
            this.linkPayer.address, this.linkPayment.mul(9)
        )).to.emit(this.arborist, 'LinkCollected').withArgs(
            this.externalAccount.address,
            this.linkPayer.address,
            this.linkPayment.mul(9)
        );
    });

    it('should allow performMassUpdate to work again now that payment balance is available', async () => {
        const [
            leaves,
            startSubtrees,
            startIndex
        ] = await this.vmtree.checkMassUpdate();

        const {root: newRoot, filledSubtrees: endSubtrees} = calculateNextRoot({
            hasher,
            startIndex,
            leaves,
            startSubtrees
        });

        const input = stringifyBigInts({
            newRoot,
            startIndex,
            startSubtrees,
            endSubtrees,
            leaves,
        });

        console.time('mass update proof');
        const { proof, publicSignals } = await generateProof({input, wasmFileName, zkeyFileName});
        console.timeEnd('mass update proof');
        const result = await verifyProof({
            proof,
            publicSignals,
            verifierJson
        });
        expect(result).to.be.true;

        const p = flattenProof(proof);

        await expect(this.vmtree.connect(this.linkNode).performMassUpdate(
            newRoot,
            endSubtrees,
            p
        )).to.emit(this.arborist, 'VMTreeHarvested').withArgs(
            this.vmtree.address,
            this.linkNode.address,
            this.linkPayer.address,
            this.linkPayment
        );
    });

    it('should have correct link balances after performMassUpdate', async () => {
        expect(await this.arborist.linkPayerBalance(this.linkPayer.address))
            .to.be.equal(this.linkPayment.mul(8));

        expect(await this.arborist.linkNodeBalance(this.linkNode.address))
            .to.be.equal(this.linkPayment);
    });

    it('should allow linkNode to withdraw payment', async () => {
        expect(await this.linkToken.balanceOf(this.arborist.address))
            .to.be.equal(this.linkPayment.mul(9));

        await expect(this.arborist.connect(this.linkNode).collectLinkNodeLink(
            this.linkNode.address
        )).to.emit(this.arborist, 'LinkCollected').withArgs(
            this.arborist.address,
            this.linkNode.address,
            this.linkPayment
        );

        expect(await this.linkToken.balanceOf(this.linkNode.address))
            .to.be.equal(this.linkPayment.mul(2));
        expect(await this.linkToken.balanceOf(this.arborist.address))
            .to.be.equal(this.linkPayment.mul(8));
    });
});