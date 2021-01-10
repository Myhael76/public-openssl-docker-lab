#!/bin/sh

export LAB_SUBJECT_TYPE="RootCA"

export LAB_SUBJ_PARAM="/CN=Examle1\ CA"
export LAB_CARTIFICATE_VALIDITY_DAYS=3700

# unsafe storage!
# if this variable is not passed, the manage function will ask for manual input
#export LAB_PK_PASS="my password"
