// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IArborist {
    function plant(address tree) external;
    function sprout() external;
    function harvest(address linkNode) external;
    function linkPayment() external view returns (uint);
    function linkPayers(address tree) external view returns (address);
    function linkPayerBalance(address linkPayer) external view returns (uint);
    function linkNodeBalance(address linkNode) external view returns (uint);
}