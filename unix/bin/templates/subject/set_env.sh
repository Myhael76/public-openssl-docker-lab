#!/bin/sh

# declare this as RootCA for self signed or Root CA certificates
# otherwise set it to something else ("IntermediateCA", "Server", "Personal")
export LAB_SUBJECT_TYPE="RootCA"

export LAB_SUBJ_PARAM="/CN=Somthing"
export LAB_CARTIFICATE_VALIDITY_DAYS=3700

# unsafe storage!
# if this variable is not passed, the manage function will ask for manual input
#export LAB_PK_PASS="my password" 

# for non RootCA certificates, this is required.
# declare here what is the subject CA (root or intermediate) that would generate the certificates for this subject
export LAB_SIGNING_CA_SUBJECT_DIR="labCA1"