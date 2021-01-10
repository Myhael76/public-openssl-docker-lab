# public-openssl-docker-lab

## Objective 
This project is an accelerator for use cases involving multiple server laboratories needed ad-hoc CA signed certificates for various purposes, including server authentication, client authentication, signing and non repudiation scenarios.

## Quick start

This is maintained with windows and docker desktop, but may be run easily in any docker environment.
The main project is docker-compose based and is found in the folder openssl-code-autohoring-helper.
It is sufficient to run the docker-compose project:

- run public-openssl-docker-lab\openssl-code-autohoring-helper\01.up.bat 
- run public-openssl-docker-lab\openssl-code-autohoring-helper\08.shell.bat
- in the new shell, run /lab_bin/manageAllSubjects.sh

To generate new certificates generate nes "subject" folders in public-openssl-docker-lab\openssl-code-autohoring-helper\data\subjects according to the provided models, then repeat the procedure

