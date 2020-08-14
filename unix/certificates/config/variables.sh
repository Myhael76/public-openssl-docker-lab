#!/bin/bash

## Edit this file according to your needs

# Certificate Authority
# variables for
# openssl ... -subj "/C=GB/ST=London/L=London/O=Global Security/OU=IT Department/CN=example.com"

LAB_CA_Country="US"
LAB_CA_Region="Oregon"
LAB_CA_City="Forest Grove"
LAB_CA_Organization="Private Laboratory"
LAB_CA_Department="IT Department"
LAB_CA_Domain="my.laboratory"

export LAB_CA_Subj="/C=${LAB_CA_Country}/ST=${LAB_CA_Region}/L=${LAB_CA_City}/O=${LAB_CA_Organization}/OU=${LAB_CA_Department}/CN=${LAB_CA_Domain}"

LAB_SERVER_COMMON_DOMAIN_SUFFIX=".mylab.info"

# Servers - as many as you want, separated by space
export LAB_SERVERS="serverA serverB serverC.intermediate1"

export LAB_KEY_BITS=4096
export LAB_PASSPHRASE="Your Passphrase Here"
