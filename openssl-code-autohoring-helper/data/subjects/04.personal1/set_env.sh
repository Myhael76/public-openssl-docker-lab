#!/bin/sh

export LAB_SUBJECT_TYPE="IntermediateCA"

export LAB_SUBJ_PARAM="/CN=Example1\ Person"
export LAB_KEY_STORE_ENTRY_NAME="Example1 person"
export LAB_CARTIFICATE_VALIDITY_DAYS=1800

# unsafe storage!
# if this variable is not passed, the manage function will ask for manual input
#export LAB_PK_PASS="my password"

export LAB_SIGNING_CA_SUBJECT_DIR="02.Interm1"
