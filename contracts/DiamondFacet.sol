pragma solidity ^0.6.3;
pragma experimental ABIEncoderV2;

/******************************************************************************\
* Author: Nick Mudge
*
* Implementation of Diamond facet.
* This is gas optimized by reducing storage reads and storage writes.
/******************************************************************************/

import "./Storage.sol";
import "./DiamondHeaders.sol";


contract DiamondFacet is Diamond, Storage {  
    bytes32 constant CLEAR_ADDRESS_MASK = 0x0000000000000000000000000000000000000000ffffffffffffffffffffffff;
    bytes32 constant CLEAR_SELECTOR_MASK = 0xffffffff00000000000000000000000000000000000000000000000000000000;

    struct SlotInfo {
        uint originalSelectorSlotsLength;                
        bytes32 selectorSlot;
        uint oldSelectorSlotsIndex;
        uint oldSelectorSlotIndex;
        bytes32 oldSelectorSlot;
        bool newSlot;
    }

    function diamondCut(bytes[] memory _diamondCut) public override {         
        require(msg.sender == $contractOwner, "Must own the contract.");
        SlotInfo memory slot;
        slot.originalSelectorSlotsLength = $selectorSlotsLength;
        uint selectorSlotsLength = uint128(slot.originalSelectorSlotsLength);
        uint selectorSlotLength = uint128(slot.originalSelectorSlotsLength >> 128);
        if(selectorSlotLength > 0) {
            slot.selectorSlot = $selectorSlots[selectorSlotsLength];
        }
        // loop through diamond cut        
        for(uint diamondCutIndex; diamondCutIndex < _diamondCut.length; diamondCutIndex++) {
            bytes memory facetCut = _diamondCut[diamondCutIndex];
            require(facetCut.length > 20, "Missing facet or selector info.");
            bytes32 currentSlot;            
            assembly { 
                currentSlot := mload(add(facetCut,32)) 
            }
            bytes32 newFacet = bytes20(currentSlot);            
            uint numSelectors = (facetCut.length - 20) / 4;
            uint position = 52;
            
            // adding or replacing functions
            if(newFacet != 0) {                
                // add and replace selectors
                for(uint selectorIndex; selectorIndex < numSelectors; selectorIndex++) {
                    bytes4 selector;
                    assembly { 
                        selector := mload(add(facetCut,position)) 
                    }
                    position += 4;                    
                    bytes32 oldFacet = $facets[selector];                    
                    // add
                    if(oldFacet == 0) {                            
                        $facets[selector] = newFacet | bytes32(selectorSlotLength) << 64 | bytes32(selectorSlotsLength);                            
                        slot.selectorSlot = slot.selectorSlot & ~(CLEAR_SELECTOR_MASK >> selectorSlotLength * 32) | bytes32(selector) >> selectorSlotLength * 32;                            
                        selectorSlotLength++;
                        if(selectorSlotLength == 8) {
                            $selectorSlots[selectorSlotsLength] = slot.selectorSlot;                                
                            slot.selectorSlot = 0;
                            selectorSlotLength = 0;
                            selectorSlotsLength++;
                            slot.newSlot = false;
                        }
                        else {
                            slot.newSlot = true;
                        }                          
                    }                    
                    // replace
                    else {
                        require(bytes20(oldFacet) != bytes20(newFacet), "Function cut to same facet.");
                        $facets[selector] = oldFacet & CLEAR_ADDRESS_MASK | newFacet;
                    }                                        
                }
            }
            // remove functions
            else {                
                for(uint selectorIndex; selectorIndex < numSelectors; selectorIndex++) {
                    bytes4 selector;
                    assembly { 
                        selector := mload(add(facetCut,position)) 
                    }
                    position += 4;                    
                    bytes32 oldFacet = $facets[selector];
                    require(oldFacet != 0, "Function doesn't exist. Can't remove.");
                    if(slot.selectorSlot == 0) {
                        selectorSlotsLength--;
                        slot.selectorSlot = $selectorSlots[selectorSlotsLength];
                        selectorSlotLength = 8;
                    }
                    slot.oldSelectorSlotsIndex = uint64(uint(oldFacet));
                    slot.oldSelectorSlotIndex = uint32(uint(oldFacet >> 64));                    
                    bytes4 lastSelector = bytes4(slot.selectorSlot << (selectorSlotLength-1) * 32);                     
                    if(slot.oldSelectorSlotsIndex != selectorSlotsLength) {
                        slot.oldSelectorSlot = $selectorSlots[slot.oldSelectorSlotsIndex];                            
                        slot.oldSelectorSlot = slot.oldSelectorSlot & ~(CLEAR_SELECTOR_MASK >> slot.oldSelectorSlotIndex * 32) | bytes32(lastSelector) >> slot.oldSelectorSlotIndex * 32;                                                
                        $selectorSlots[slot.oldSelectorSlotsIndex] = slot.oldSelectorSlot;                        
                        selectorSlotLength--;                            
                    }
                    else {
                        slot.selectorSlot = slot.selectorSlot & ~(CLEAR_SELECTOR_MASK >> slot.oldSelectorSlotIndex * 32) | bytes32(lastSelector) >> slot.oldSelectorSlotIndex * 32;
                        selectorSlotLength--;
                    }
                    if(selectorSlotLength == 0) {
                        delete $selectorSlots[selectorSlotsLength];                                                
                        slot.selectorSlot = 0;
                    }
                    if(lastSelector != selector) {                      
                        $facets[lastSelector] = oldFacet & CLEAR_ADDRESS_MASK | bytes20($facets[lastSelector]); 
                    }
                    delete $facets[selector];
                }
            }
        }
        uint newSelectorSlotsLength = selectorSlotLength << 128 | selectorSlotsLength;
        if(newSelectorSlotsLength != slot.originalSelectorSlotsLength) {
            $selectorSlotsLength = newSelectorSlotsLength;            
        }        
        if(slot.newSlot) {
            $selectorSlots[selectorSlotsLength] = slot.selectorSlot;                        
        }
        emit DiamondCut(_diamondCut);
    }
}
