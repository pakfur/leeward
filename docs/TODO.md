# TODO

This file contains a mishmash of bugs, qol issues, things I want to fix, 
big features, small features, etc. 
Basically a durable memory file for things that are important to me I want to 
fix/change/add/remove and don't want to forget about.


## BUGS


## QoL Changes

### Movement Validator
- protocol response valid_next_hexes also return a set of tokens for each
  hex that reflect the specific reason why a hex is 
  not allowed. 1 or more tokens per hex.  Token is "XXXX:<desc>",
  where XXXX is a globally uniqe id, and <desc> describes what the violation is.
  (ie "XXXX:MA <= 0", "YYYY:Violates Turning Minimum")
  Each condition is associated with a unique code, and fixed short desc.
  The codes will be used later for UI reasons

### Developer UI
- allow the developer UI window to be resized horizontally, with a fixed min.
- improve the usability of the trace window (wider window, wrap on/off)

## New Features
