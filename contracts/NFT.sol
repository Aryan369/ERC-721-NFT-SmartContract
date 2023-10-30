// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts@4.7.3/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.7.3/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts@4.7.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.7.3/utils/Counters.sol";
import "@openzeppelin/contracts@4.7.3/utils/math/SafeMath.sol";
import "@openzeppelin/contracts@4.7.3/utils/Strings.sol";
import "@openzeppelin/contracts@4.7.3/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts@4.7.3/security/ReentrancyGuard.sol";

contract CICADA3301 is ERC721, ERC721Enumerable, ERC721Burnable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    uint256 private tokenURIOffset;
    uint256 public maxMintAmountPerTx = 20;
    uint256 public MAX_CICADA = 3301;
    uint256 private RESERVED_CICADA = 33;
    uint256 public mintPrice = 0.000001 ether; //7000

    string public baseURI;

    bool public secondarySalesWithdraw;
    bool public paused;
    bool public burnPaused;
    bool public revealed;
    bool public preSale;
    bool public preSaleTanuki;

    bytes32 private root;
    bytes32 private rootTanuki;
    bytes32 private rootClaim;

    mapping (address => bool) preSaleTanukiClaimed;
    mapping (address => bool) preSaleClaimed;
    mapping (address => bool) cicadaClaimed;

    constructor(string memory baseURI_) ERC721("CICADA 3301", "SECRET") {
        setBaseURI(baseURI_);
        setTokenURIOffset();
    }

    function mint(uint256 numberOfTokens) nonReentrant public payable {
        require(!paused, "THE GATES ARE CLOSED");
        require(totalSupply().add(numberOfTokens) <= MAX_CICADA, "Not enough tokens left.");
        require(numberOfTokens <= maxMintAmountPerTx && numberOfTokens > 0, "Max mint amount per transaction is 10.");
        
        require(msg.value >= mintPrice.mul(numberOfTokens), "Not enough ether sent.");

        for(uint256 i = 0; i < numberOfTokens; i++){
            if(totalSupply() < MAX_CICADA){
                if(preSaleTanuki){
                    preSaleTanukiClaimed[msg.sender] = true;
                }
                else if (preSale){
                    preSaleClaimed[msg.sender] = true;
                }

                _tokenIdCounter.increment();
                uint256 tokenId = _tokenIdCounter.current();
                _safeMint(msg.sender, tokenId);
            }
        }
    }

    function presaleMint(bytes32[] memory proof) nonReentrant public payable {
        require(!paused, "THE GATES ARE CLOSED");
        require(totalSupply() < MAX_CICADA, "Not enough tokens left.");
        require(preSaleTanuki || preSale, "THE GATES ARE CLOSED");

        require(msg.value >= mintPrice, "Not enough ether sent.");

        if(preSaleTanuki){
            require(isValidTanuki(proof, keccak256(abi.encodePacked(msg.sender))), "THE GATES ONLY OPEN FOR THE CHOSEN ONES");
            require(preSaleTanukiClaimed[msg.sender] == false, "You have already claimed");
            preSaleTanukiClaimed[msg.sender] = true;
        }
        else if (preSale){
            require(isValid(proof, keccak256(abi.encodePacked(msg.sender))), "THE GATES ONLY OPEN FOR THE CHOSEN ONES");
            require(preSaleClaimed[msg.sender] == false, "You have already claimed");
            preSaleClaimed[msg.sender] = true;
        }

        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(msg.sender, tokenId);
    }

    function reserveCICADA() external onlyOwner {
        for(uint256 i = 0; i < RESERVED_CICADA; i++){
            if(totalSupply() < MAX_CICADA){
                _tokenIdCounter.increment();
                uint256 tokenId = _tokenIdCounter.current();
                _safeMint(msg.sender, tokenId);
            }
        }
    }

    function claimCICADA(bytes32[] memory proof) nonReentrant external {
        require(!paused, "THE GATES ARE CLOSED");
        require(isValidClaim(proof, keccak256(abi.encodePacked(msg.sender))), "YOU ARE NOT A CHOSEN ONE");
        require(cicadaClaimed[msg.sender] == false, "You have already claimed.");

        if(totalSupply() < MAX_CICADA){
            cicadaClaimed[msg.sender] = true;
            _tokenIdCounter.increment();
            uint256 tokenId = _tokenIdCounter.current();
            _safeMint(msg.sender, tokenId);
        }
    }

    // Burn /////////////////////////////////////////
    function burn(uint256 tokenId) public override  {
        require(!burnPaused, "Burning is paused");
        burn(tokenId);
    }

    function setBurnPaused(bool _state) public onlyOwner {
        burnPaused = _state;
    }

    ////////////////////////////////////////////////

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // URI ///////////////////////////////////////

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI_ = _baseURI();

        tokenId = tokenId.add(tokenURIOffset);
        if(!(tokenId <= MAX_CICADA)){
            tokenId -= MAX_CICADA; 
        }

        if(revealed){
            // return bytes(baseURI_).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json")) : "";
            return bytes(baseURI_).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId))) : "";
        }
        else{
            return string(abi.encodePacked(baseURI));
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    //////////////////////////////////////////////


    /////////////////// Withdraw //////////////////////////////////

    function withdraw() external payable onlyOwner {
        if(!secondarySalesWithdraw){
            if(totalSupply() == MAX_CICADA){
                secondarySalesWithdraw = true;
            }

            (bool success, ) = payable(owner()).call{value: address(this).balance}("");
            require(success);
        }
        else {
            // (bool success, ) = payable(owner()).call{value: address(this).balance}("");
            // require(success);
        }    
    }

    /////////////////////////////////////////////////////////////////

    function setMintPrice(uint256 _mintPrice) public onlyOwner {
        mintPrice = _mintPrice;
    }

    function setBaseURI(string memory baseURI_) public  onlyOwner {
        baseURI = baseURI_;
    }

    function setRevealed(bool _state) public onlyOwner{
        revealed = _state;
    }

    function setPaused(bool _state) public onlyOwner {
        paused = _state;
    }

    // Random Token URI ///////////////////////

    function setTokenURIOffset() private {
        require(tokenURIOffset == 0);
        tokenURIOffset = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp))) % MAX_CICADA;
    }

    ///////////////////////////////////////////

    function walletOfOwner(address _owner) external view returns (uint256[] memory){
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        uint256 currentTokenId = 1;
        uint256 ownedTokenIndex = 0;

        while (ownedTokenIndex < ownerTokenCount && currentTokenId <= MAX_CICADA) {
            address currentTokenOwner = ownerOf(currentTokenId);

            if (currentTokenOwner == _owner) {
                ownedTokenIds[ownedTokenIndex] = currentTokenId;

                ownedTokenIndex++;
            }

            currentTokenId++;
        }

        return ownedTokenIds;
    }

    // Merkle Proof ////////////////////////////

    function isValid(bytes32[] memory proof, bytes32 leaf) public view returns(bool) {
        return MerkleProof.verify(proof, root, leaf);
    }

    function isValidTanuki(bytes32[] memory proof, bytes32 leaf) public view returns(bool) {
        return MerkleProof.verify(proof, rootTanuki, leaf);
    }

    function isValidClaim(bytes32[] memory proof, bytes32 leaf) public view returns(bool) {
        return MerkleProof.verify(proof, rootClaim, leaf);
    }

    // setter
    function setRoot(bytes32 _root) external onlyOwner{
        root = _root;
    }

    function setRootTanuki(bytes32 _root) external onlyOwner{
        rootTanuki = _root;
    }

    function setRootClaim(bytes32 _root) external onlyOwner{
        rootClaim = _root;
    }
    
    /////////////////////////////////////////////

    function setPresale(bool _state) external onlyOwner{
        preSale = _state;
    }

    function setPresaleTanuki(bool _state) external onlyOwner{
        preSaleTanuki = _state;
    }

    /////////////////////////////////////////////
}
