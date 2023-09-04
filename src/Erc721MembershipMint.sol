//SPDX-License-Identifier: MIT
//developed for the first membership card mint of PretzelDAO
pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract Erc721MembershipMint is ERC721, AccessControl {
    using Strings for uint256;

    bytes32 public constant ADMIN = keccak256("ADMIN");

    //price - without the decimals - so 50USDC -> 50
    uint256 public price;

    //allowlists - membership number == token id -> allowlist already sets the id so a member will have the same ID every year
    mapping(address => uint256) public allowlistWithId;

    //customization options for NFTs
    mapping(address => string) public addressToCustomizedImageUrl;
    mapping(address => string) public addressToCustomizedMemberRole;

    string public defaultImageUrl;
    string public defaultMemberRole;

    IERC20 public paymentTokenContract; //Polygon USDC: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
    uint256 public paymentTokenContractDecimals; //Polygon USDC: 6

    address public treasury;

    string public baseUri;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _baseUri,
        address _paymentTokenContract,
        uint256 _paymentTokenContractDecimals,
        uint256 _price,
        address _treasury,
        string memory _defaultImageUrl,
        string memory _defaultMemberRole
    ) ERC721(_name, _symbol) {
        _grantRole(ADMIN, msg.sender);
        paymentTokenContract = IERC20(_paymentTokenContract);
        paymentTokenContractDecimals = _paymentTokenContractDecimals;
        treasury = _treasury;
        baseUri = _baseUri; //assumption: all NFTs are the same -> containing an image and the year of the membership
        price = _price;
        defaultImageUrl = _defaultImageUrl;
        defaultMemberRole = _defaultMemberRole;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    //this is a soulbound token - only the ADMIN can move a token
    function transferFrom(address from, address to, uint256 id) public virtual override onlyRole(ADMIN) {
        _transfer(from, to, id);
    }

    //this is a soulbound token - only the ADMIN can move a token
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public virtual override onlyRole(ADMIN) {
        _safeTransfer(from, to, id, data);
    }

    //this is a soulbound token - only the ADMIN can move a token
    function safeTransferFrom(address from, address to, uint256 id) public virtual override onlyRole(ADMIN) {
        safeTransferFrom(from, to, id, "");
    }

    function mint() public {
        require(allowlistWithId[msg.sender] != 0, "not allowlisted");
        //allowance for payment Token needs to be set - requires call of increaseAllowance(address spender, uint256 addedValue) on the payment token contract beforehand
        require(
            paymentTokenContract.allowance(msg.sender, address(this)) >=
                price * 10 ** paymentTokenContractDecimals,
            "not enough allowance for payment token"
        );
        uint256 id = allowlistWithId[msg.sender];
        //send the payment token to the treasury
        paymentTokenContract.transferFrom(msg.sender, treasury, price * 10 ** paymentTokenContractDecimals);
        //remove from allowlist
        allowlistWithId[msg.sender] = 0;
        _safeMint(msg.sender, id, "");
    }

    function freeMint(address _to, uint256 _id) public onlyRole(ADMIN) {
        _safeMint(_to, _id, "");
    }

    // Add an address to the allowlist
    function addToAllowlist(address _address, uint256 _reservedTokenId) external onlyRole(ADMIN) {
        allowlistWithId[_address] = _reservedTokenId;
    }

    function addBatchToAllowlist(address[] memory _addresses, uint256[] memory _ids) external onlyRole(ADMIN) {
        require(_ids.length == _addresses.length, "ids and addresses length mismatch");
        for (uint256 i = 0; i < _ids.length; i++) {
            allowlistWithId[_addresses[i]] = _ids[i];
        }
    }

    function removeBatchFromAllowlist(address[] memory _addresses) external onlyRole(ADMIN) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            allowlistWithId[_addresses[i]] = 0;
        }
    }

    // Remove an address from the allowlist
    function removeFromAllowlist(address _address) external onlyRole(ADMIN) {
        allowlistWithId[_address] = 0;
    }

    //SETTERS

    function setPrice(uint256 _price) external onlyRole(ADMIN) {
        price = _price;
    }

    function setTreasury(address _treasury) external onlyRole(ADMIN) {
        treasury = _treasury;
    }

    function setImageUrl(address _address, string memory _imageUrl) external onlyRole(ADMIN) {
        addressToCustomizedImageUrl[_address] = _imageUrl;
    }

    function getImageUrl(uint256 _tokenId) public view returns (string memory) {
        if (bytes(addressToCustomizedImageUrl[ownerOf(_tokenId)]).length > 0) {
            return addressToCustomizedImageUrl[ownerOf(_tokenId)];
        }
        return defaultImageUrl;
    }

    function setMemberRole(address _address, string memory _memberRole) external onlyRole(ADMIN) {
        addressToCustomizedMemberRole[_address] = _memberRole;
    }

    function getMemberRole(uint256 _tokenId) public view returns (string memory) {
        if (bytes(addressToCustomizedMemberRole[ownerOf(_tokenId)]).length > 0) {
            return addressToCustomizedMemberRole[ownerOf(_tokenId)];
        }
        return defaultMemberRole;
    }


    struct TokenMetadata {
        string tokenId;
        string imageUrl;
        string memberRole;

    }   
    //assumption: each token has the same meta data - image and year of the membership
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        _requireMinted(_tokenId);

        TokenMetadata memory tokenMetadata;

        tokenMetadata.tokenId = Strings.toString(_tokenId);
        tokenMetadata.imageUrl = getImageUrl(_tokenId);
        tokenMetadata.memberRole = getMemberRole(_tokenId);

        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "PretzelDAO Membership Card 2023 #', tokenMetadata.tokenId, '",',
                '"description": "PretzelDAO e.V. Membership Card for the year 2023, one per active and verified member. Membership Card NFT is used as a governance token for the DAO. The token is soulbound and can only be transferred by the board of the PretzelDAO e.V.",',
                '"image": "', tokenMetadata.imageUrl, '","token_id": ', tokenMetadata.tokenId, ',"external_url":"https://pretzeldao.com/",',
                '"attributes":[{"trait_type": "Edition","value": "2023"}, {"key":"Type","trait_type":"Type","value":"Governance Token"},',
                '{"display_type": "date","trait_type":"Valid until","value":1704063599},{"trait_type": "Member Role","value": "', tokenMetadata.memberRole, '"}]'
            '}'
        );
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    function setPaymentTokenContract(address _paymentTokenContract) external onlyRole(ADMIN) {
        paymentTokenContract = IERC20(_paymentTokenContract);
    }

    function setPaymentTokenContractDecimals(uint256 _paymentTokenContractDecimals) external onlyRole(ADMIN) {
        paymentTokenContractDecimals = _paymentTokenContractDecimals;
    }

    //ROLE MANAGEMENT
    function grantAdmin(address _admin) public onlyRole(ADMIN) {
        _grantRole(ADMIN, _admin);
    }

    function revokeAdmin(address _admin) public onlyRole(ADMIN) {
        _revokeRole(ADMIN, _admin);
    }
}
