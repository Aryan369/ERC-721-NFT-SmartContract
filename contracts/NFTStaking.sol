// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts@4.7.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.7.3/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts@4.7.3/utils/Counters.sol";

interface INFT {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
}

contract SacredTemple is Ownable, ERC721Holder, ReentrancyGuard {
    address _nftContract;

    using Counters for Counters.Counter;
    Counters.Counter private _stakedNFTCounter;

    event NFTStaked(address owner, uint256 tokenId, uint256 value);
    event NFTUnstaked(address owner, uint256 tokenId, uint256 value);
    event Claimed(address owner, uint256 amount);

    mapping (uint256 => address) public tokenOwnerOf;
    mapping (uint256 => uint256) public rewards;
    uint256[] tokenStaked;

    constructor (address nftContract_) {
        _nftContract = nftContract_;
    }

    function setNftContact(address nftContract_) external onlyOwner {
        _nftContract = nftContract_;
    }

    function stake(uint256 tokenId) external {
        IERC721(_nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        tokenOwnerOf[tokenId] = msg.sender;
        tokenStaked.push(tokenId);
        _stakedNFTCounter.increment();
    }

    function unstake(uint256 tokenId) nonReentrant external {
        require(tokenOwnerOf[tokenId] == msg.sender, "You are not the owner.");
        delete tokenOwnerOf[tokenId];
        _stakedNFTCounter.decrement();
        (bool success, ) = payable(tokenOwnerOf[tokenId]).call{value: rewards[tokenId]}("");
        require(success);
        delete rewards[tokenId];
        IERC721(_nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function claim(uint256 tokenId) nonReentrant external {
        require(tokenOwnerOf[tokenId] == msg.sender, "You are not the owner.");
        (bool success, ) = payable(tokenOwnerOf[tokenId]).call{value: rewards[tokenId]}("");
        require(success);
        rewards[tokenId] = 0;
    }

    function calculateRewards(uint256 tokenId) public view returns(uint256){
        return rewards[tokenId];
    }

    function getTokensStakedByUser(address _address) public view returns(uint256[] memory){
        uint256[] memory _tokenStaked = INFT(_nftContract).walletOfOwner(address(this));
        uint256[] memory tokenOwnerOfUser = new uint256[](_tokenStaked.length);
        uint256 currentIndex = 0;

        for (uint i; i < _tokenStaked.length; i++){
            uint256 tokenId = _tokenStaked[i];
            if(_address == tokenOwnerOf[tokenId]){
                tokenOwnerOfUser[currentIndex] = tokenId;
                currentIndex++;
            }
        }
        return tokenOwnerOfUser;
    }

    receive() external payable {
        require(_stakedNFTCounter.current() != 0, "No NFTs are staked");
        uint256 sharePerEach = msg.value / _stakedNFTCounter.current();
        uint256[] memory tokensStaked = INFT(_nftContract).walletOfOwner(address(this));
        
        for(uint256 i = 0; i < tokensStaked.length;){
            rewards[tokenStaked[i]] += sharePerEach;
            unchecked {++i;}
        }
    }
}