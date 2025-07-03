
# Synapse: Matrix homeserver fast install script. Matrix Synapse + PostgreSQL + Admin UI + Element WEB + Coturn(Audio&amp;Video calls)


#### Synapse is an open-source Matrix homeserver
#### Matrix supports encryption and VoIP. Matrix is ​​an open protocol for decentralized and secure communication.
#### https://github.com/matrix-org/synapse


### Allows you to run your own standalone messenger server with encryption, audio and video calls. With applications for any device



## Clients:
For Mac and Windows: https://element.io/download 

For Iphone: https://apps.apple.com/us/app/element-messenger/id1083446067 

For Android: https://play.google.com/store/apps/details?id=im.vector.app&pli=1 



## Install 
System requirements:
Ubuntu 20.04

To install, log into your server via ssh and run the command as root:
```
wget https://raw.githubusercontent.com/JustUnknownDude/matrix-synapse/main/setup.sh && bash setup.sh
```
If you need a version with federation enabled use this file:
```
wget https://raw.githubusercontent.com/JustUnknownDude/matrix-synapse/main/setup-with-federation.sh && bash setup-with-federation.sh
```
P.S. The version with the federation option enabled should work, but I don't have time to test it.
