just use init script.
dependencies for package manager:
wget. thats it. preferably make-ca, but you can just edit the package manager to pass --no-check-certificate.
(assuming you have internet)

for testing reasons, hello depends on cmatrix (just to see if dep resolution works)

please edit /etc/pkg/pkg.conf (placeholder name) and add MAKEFLAGS CXXFLAGS, whatever you want

## goals
- testing suite (tests for safety, but build already builds)
- better cli, more error handling
- integ checks
- this is actually just a funny project, very unlikely to become something usuable (for the average joe) 

i am aware this is slightly unoriginal, however im bored.
ill probably redo stuff in c++ when i complete this, and make it better (in the sense of cleaner code, less random shit, and more original) 

## recent adds:
fixed the funny fucking error causing the 'install' command to literally call install, making builds last fucking forever!
added a custom patch system that doesn't require a specific patcher, just does it
thats basically it, but i also made it oragnizable in directories and a bit more that im lazy to list (note: i fucking hate copilot auto commit message) 
