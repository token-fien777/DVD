const {BN, constants, expectEvent} = require('@openzeppelin/test-helpers');

const DVGToken = artifacts.require("DVGToken");

contract("DVGToken", async (accounts) => {

  it("Should mint some DVGs in advance when deploying DVGToken smart contract", async () => {
    var amount = new BN('10000000000000000000');

    var dvg = await DVGToken.new(accounts[1], amount);

    console.log("DVG token smart contract address:", dvg.address);

    assert.equal(await dvg.name(), 'DVGToken', 'DVG token name disagreement');
    assert.equal(await dvg.symbol(), 'DVG', 'DVG token symbol disagreement');
    assert.equal(await dvg.decimals(), 18, 'DVG token decimals disagreement');
    assert.equal((await dvg.totalSupply()).toString(), amount, 'DVG token supply disagreement');
    assert.equal((await dvg.balanceOf(accounts[1])).toString(), amount, 'should mint some DVGs to accounts[1] in advance when deploying');
      
    await expectEvent.inConstruction(dvg, 'Transfer', {from:constants.ZERO_ADDRESS, to:accounts[1], value:amount});
  });

});
