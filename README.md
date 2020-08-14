# public-openssl-docker-lab

This project is an accelerator for use cases involving multiple server laboratories needed ad-hoc CA signed certificates for various purposes, including server authentication, client authentication, signing and non repudiation scenarios.

This is maintained with windows and docker desktop, but may be run easily in any docker environment.

The main project is docker-compose based and is found in the folder docker-compose.

It is sufficient to run the project.

Configuration about what certificates to generate is found in unix/certificates/config folder.

Declare a custom passphrase and the list of servers in variables.sh.

For each server declare the alternate names in the file /unix/certificates/config/server_${serverName}/altNames.config file.

For the rest the code is very simple and the relative options are easily discoverable.

Each "up" command spins up an alpine based openssl container, generates the certificates as configured and exits. At the moment the automatic exit is suspended for troubleshooting reasons, stop the project explictly.

