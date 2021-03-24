#!/bin/sh

######### Project constants
# this script position: /root/certificates
export RED='\033[0;31m'
export NC='\033[0m' 				  	# No Color
export Green="\033[0;32m"        		# Green
export Cyan="\033[0;36m"         		# Cyan

if [ -z "${LOG_TOKEN}" ]; then
    LOG_TOKEN="PUBLIC_CERT_LAB Common"
fi
LOG_TOKEN_C_I="${Green}INFO - ${LOG_TOKEN}${NC}"
LOG_TOKEN_C_E="${RED}ERROR - ${Green}${LOG_TOKEN}${NC}"

logI(){
    echo -e `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN_C_I} - ${1}"
    echo `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN} -INFO- ${1}" >> ${LAB_RUN_FOLDER}/script.trace.log
}

logE(){
    echo -e `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN_C_E} - ${RED}${1}${NC}"
    echo `date +%y-%m-%dT%H.%M.%S_%3N`" ${LOG_TOKEN} -ERROR- ${1}" >> ${LAB_RUN_FOLDER}/script.trace.log
}

showLabEnv(){
    env | sort | grep LAB_
}

### Attempt to source the custom set_env shell
LAB_SET_ENV_SHELL=${LAB_SET_ENV_SHELL:-"/tmp/no_set_env_file_passed.sh"}

if [ -f ${LAB_SET_ENV_SHELL} ]; then
    logI "Sourcing custom set_env file ${LAB_SET_ENV_SHELL}"
    . ${LAB_SET_ENV_SHELL}
fi

### Context defaults, if they are not passed
export LAB_SUBJECTS_FOLDER=${LAB_SUBJECTS_FOLDER:-"/data/subjects"}
export LAB_KEY_BIT=${LAB_KEY_BITS:-4096}
export LAB_RUN_FOLDER=${LAB_RUN_FOLDER:-"/tmp/runs"}
mkdir -p ${LAB_RUN_FOLDER}

genKeysForSubject(){
    # Generates a private encrypted keypair
    # Params
    # $1 subject folder name (no path, no slashes)
    # $2 encryption passphrase

    if [ -z "${2}" ]; then
        logE "genKeysForSubject(): Must pass a passphrase in the second parameter"
    else
        if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
            logI "genKeysForSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1}/out already has a key pair"
        else
            logI "Generating private key pair for subject ${1}"
            openssl genrsa \
                -aes256 \
                -passout pass:"${2}" \
                -out "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
                ${LAB_KEY_BITS}
        fi
    fi
}

genCsrForSubject(){
    # If we run as CA, the CSR should be received from requesters. In this case put them in the following location
    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.csr" ]; then
        logI "genCsrForSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1}/out already has a CSR"
    else
        genKeysForSubject "$1" "$2" # just in case the keypair was not generated upfront
        openssl req \
            -new \
            -sha256 \
            -key "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
            -passin pass:"${2}" \
            -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.csr" \
            -config "${LAB_SUBJECTS_FOLDER}/${1}/csr.config"
    fi
}

genRootCaCert(){
    # Generates a self signed certificate usable normally for a ROOT CA
    # Params
    # $1 subject folder name (no path, no slashes)
    # $2 encryption passphrase

    if [ -z "${2}" ]; then
        logE "genRootCaCert(): Must pass a passphrase in the second parameter"
    else
        genKeysForSubject "$1" "$2" # just in case the keypair was not generated upfront
        if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
            logI "Certificate ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer already exist, nothing to do"
        else
            logI "Generating self signed Root CA Certificate for subject ${1}"
            openssl req \
                -new \
                -key "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
                -passin pass:"${2}" \
                -x509 \
                -days ${LAB_CARTIFICATE_VALIDITY_DAYS} \
                -subj "${LAB_SUBJ_PARAM}" \
                -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
            cat "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" > "${LAB_SUBJECTS_FOLDER}/${1}/out/public.crt.bundle.pem"
            logI "Key ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer generated"
        fi
    fi
}

genCertForSubject(){
    # params
    # $1 - subject
    # $2 - passphrase for subject's PK
    if [ -z "${2}" ]; then
        logE "genRootCaCert(): Must pass a passphrase in the second parameter"
    else
        if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
            logI "Certificate ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer already exist, nothing to do"
        else
            # genKeysForSubject "${1}" "${2}"
            # CSR
            genCsrForSubject "${1}" "${2}"

            pwdCA=$(getPKPassForSubjectFromMemStore "${LAB_SIGNING_CA_SUBJECT_DIR}")

            openssl x509 \
                -req \
                -days "${LAB_CARTIFICATE_VALIDITY_DAYS}" \
                -in "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.csr" \
                -CA "${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/public.pem.cer" \
                -CAkey "${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/private.encrypted.keypair.pem" \
                -passin pass:"${pwdCA}" \
                -CAcreateserial \
                -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
                -extfile "${LAB_SUBJECTS_FOLDER}/${1}/certGen.config" \
                -extensions LAB

            cat \
                "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
                "${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/public.crt.bundle.pem" \
                > "${LAB_SUBJECTS_FOLDER}/${1}/out/public.crt.bundle.pem"

            unset pwdCA
        fi
    fi
}

genKeyCertBundleForSubject(){
    # params
    # $1 - subject
    logI "Generating key and certificate private bundle for subject ${1}"
    cat \
        "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        > "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.cert.bundle.pem"
}

generateP12PrivateKeyStoreForSubject(){
    # Note: 
    # for longer chains the -certfile must contain the full bundle up to the current certificate
    # excluding the one passed with -inkey
    logI "Generate PKCS#12 key store without chain for subject ${1}..."
    openssl pkcs12 \
        -export \
        -in "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        -inkey "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        -passin pass:"${2}" \
        -out "${LAB_SUBJECTS_FOLDER}/${1}/out/private.key.store.p12"  \
        -passout pass:"${2}" \
        -CAfile "${LAB_SUBJECTS_FOLDER}/${3}/out/public.pem.cer"
#        -passin pass:"${2}" \

}

generateP12PrivateKeyStoreWithChainForSubject(){
    # Note: 
    # for longer chains the -certfile must contain the full bundle up to the current certificate
    # excluding the one passed with -inkey
    logI "Generate PKCS#12 key store with chain for subject ${1}..."
    openssl pkcs12 \
        -export \
        -in "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        -inkey "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        -passin pass:"${2}" \
        -out "${LAB_SUBJECTS_FOLDER}/${1}/out/full.chain.key.store.p12"  \
        -passout pass:"${2}" \
        -name "${LAB_KEY_STORE_ENTRY_NAME}" \
        -CAfile "${LAB_SUBJECTS_FOLDER}/${3}/out/public.crt.bundle.pem" \
        -caname "${LAB_ROOT_CA_NAME}" \
        -chain
}

sourceSubjectLocalVars(){
    logI "Sourcing file ${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh"
    . "${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh"
    # defaults
    LAB_KEY_BITS=${LAB_KEY_BITS:-4096}
    LAB_CARTIFICATE_VALIDITY_DAYS=${LAB_CARTIFICATE_VALIDITY_DAYS:-365}
}

unsetSubjectLocals(){
    # cleanup subject related variables
    unset \
        LAB_SUBJECT_TYPE \
        LAB_SUBJ_PARAM \
        LAB_CARTIFICATE_VALIDITY_DAYS \
        LAB_PK_PASS \
        LAB_SIGNING_CA_SUBJECT_DIR \
        LAB_SIGNING_ROOT_CA_SUBJECT_DIR
}

readSecretFromUser(){
    # params
    # $1 - message -> what to input
    secret="0"
    while [ "${secret}" == "0" ]; do
        read -sp "Please input ${1}: " s1
        echo ""
        read -sp "Please input ${1} again: " s2
        echo ""
        if [ "${s1}" == "${s2}" ]; then
            secret=${s1}
        else
            echo "Input do not match, retry"
        fi
        unset s1 s2
    done
}

assurePKPasswordForSubject(){
    # params
    # $1 subject
    if [ ! -f "/dev/shm/certPasses/${1}/pass.tmp" ]; then
        if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh" ]; then
            logI "Sourcing local env vars for subject ${1}"
            . "${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh"
        fi
        if [ -z "${LAB_PK_PASS}" ]; then
            readSecretFromUser " private key passphrase for subject ${1}"
            mkdir -p "/dev/shm/certPasses/${1}"
            echo "${secret}" > "/dev/shm/certPasses/${1}/pass.tmp"
            unset secret
        else
            echo "${LAB_PK_PASS}" > "/dev/shm/certPasses/${1}/pass.tmp"
        fi
    fi
    unsetSubjectLocals
}

getPKPassForSubjectFromMemStore(){
    # params
    # $1 subject
    if [ -f "/dev/shm/certPasses/${1}/pass.tmp" ]; then
        cat "/dev/shm/certPasses/${1}/pass.tmp"
    else
        echo "password not set"
    fi
}

manageSubject(){
    # Params
    # $1 -> Subject folder
    logI "Treating subject ${1}"
    if [ -d "${LAB_SUBJECTS_FOLDER}/${1}" ] ; then
        if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh" ]; then
            sourceSubjectLocalVars "${1}"
            # check passphrase
            if [ -z "${LAB_PK_PASS}" ]; then
                LAB_PK_PASS=$(getPKPassForSubjectFromMemStore "${1}")
                logI "LAB_PK_PASS for subject ${1} recovered from memory cache"
            fi
            mkdir -p "${LAB_SUBJECTS_FOLDER}/${1}/out"
            if [ "${LAB_SUBJECT_TYPE}" == "RootCA" ]; then
                genRootCaCert "${1}" "${LAB_PK_PASS}"
            else
                logI "Managing CSR for subject ${1}"
                genCsrForSubject "${1}" "${LAB_PK_PASS}"
                logI "Managing PEM Certificate stores for subject ${1}"
                genCertForSubject "${1}" "${LAB_PK_PASS}"
                genKeyCertBundleForSubject "${1}"
                logI "Managing PKCS12 Certificate stores for subject ${1}"
                generateP12PrivateKeyStoreForSubject "${1}" "${LAB_PK_PASS}" "${LAB_SIGNING_CA_SUBJECT_DIR}"
                generateP12PrivateKeyStoreWithChainForSubject "${1}" "${LAB_PK_PASS}" "${LAB_SIGNING_CA_SUBJECT_DIR}"
            fi
            unsetSubjectLocals
        else
            logE "manageSubject(): Subject set_env.sh file missing, cannot manage this subject"
        fi
    else
        logE "manageSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1} not found!"
    fi
}

manageAllSubjects(){
    logI "Treating all subjects in folder ${LAB_SUBJECTS_FOLDER}"
    oldpath=`pwd`
    #pushd . >/dev/null
    cd "${LAB_SUBJECTS_FOLDER}/"
    for subjectDir in * ; do
        assurePKPasswordForSubject ${subjectDir}
        manageSubject ${subjectDir}
    done
    #popd /dev/null
    cd "${oldpath}"
}