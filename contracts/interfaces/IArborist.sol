// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IArborist {
    /*
        Views
    */
    function vmTreeTemplate() external view returns (address);
    function linkToken() external view returns (address);
    function linkPayment() external view returns (uint);
    function linkPayers(address tree) external view returns (address);
    function linkPayerBalance(address linkPayer) external view returns (uint);
    function linkNodeBalance(address linkNode) external view returns (uint);
    function checkTreeBalance(address tree) external view returns (uint);

    /*
        Mutators
    */
    function onTokenTransfer(
        address sender,
        uint amount,
        bytes calldata data
    ) external;
    function sprout() external;
    function harvest(address linkNode) external;
    function collectLinkNodeLink(address to) external;
    function collectLinkPayerLink(address to, uint amount) external;
    function topUpLink(address linkPayer, uint amount) external;
}