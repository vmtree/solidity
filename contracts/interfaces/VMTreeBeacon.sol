// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface VMTreeBeacon {
    function plant(address tree) external;
    function sprout() external;
    function harvest(address linkNode) external;
}