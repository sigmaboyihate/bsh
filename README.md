just use init script.
dependencies for package manager:
wget. thats it. preferably make-ca, but you can just edit the package manager to pass --no-check-certificate.
(assuming you have internet)

for testing reasons, hello depends on cmatrix (just to see if dep resolution works)

## goals
- testing suite (tests for safety, but build already builds)
- better cli, more error handling 

i am aware this is slightly unoriginal, however im bored.
ill probably redo stuff in c++ when i complete this, and make it better (in the sense of cleaner code, less random shit, and more original) 
