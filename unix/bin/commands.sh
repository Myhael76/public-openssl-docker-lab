#!/bin/sh

######### Project constants
# this script position: /root/certificates
export RED='\033[0;31m'
export NC='\033[0m' 				  	# No Color
export Green="\033[0;32m"        		# Green
export Cyan="\033[0;36m"         		# Cyan

ERR_FS_MISSING=101

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

    if [ -z "${1}" ]; then
        logE "genKeysForSubject(): Must pass a subject directory in the first parameter"
        return 101
    fi
    if [ -z "${2}" ]; then
        logE "genKeysForSubject(): Must pass a passphrase in the second parameter"
        return 102
    fi

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
        logI "genKeysForSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1}/out already has a key pair"
    else
        logI "genKeysForSubject(): Generating private key pair for subject ${1}"
        openssl genrsa \
            -aes256 \
            -passout pass:"${2}" \
            -out "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
            ${LAB_KEY_BITS}
        local result=$?
        if [ "$result" -ne 0 ]; then
            logE "genKeysForSubject(): Key pair generation for subject ${1} failed with result code $result"
            return 1
        fi
    fi

}

genCsrForSubject(){
    # validations
    if [ -z "${1}" ]; then
        logE "genCsrForSubject(): Must pass a subject directory in the first parameter"
        return 101
    fi
    if [ ! -d "${LAB_SUBJECTS_FOLDER}/${1}" ]; then
        logE "genCsrForSubject(): Not a directory: ${LAB_SUBJECTS_FOLDER}/${1}"
        return 102
    fi

    # If we run as CA, the CSR should be received from requesters. In this case put them in the following location
    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.csr" ]; then
        logI "genCsrForSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1}/out already has a CSR"
        return 0
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
        logE "genCsrForSubject(): Private keypair file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem"
        return 103
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/csr.config"]; then
        logE "genCsrForSubject(): CSR config file not found: ${LAB_SUBJECTS_FOLDER}/${1}/csr.config"
        return 104
    fi

    logI "genCsrForSubject(): Generating CSR for subject ${1}..."
    genKeysForSubject "$1" "$2" || return $? # just in case the keypair was not generated upfront
    openssl req \
        -new \
        -sha256 \
        -key "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        -passin pass:"${2}" \
        -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.csr" \
        -config "${LAB_SUBJECTS_FOLDER}/${1}/csr.config"
    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "genCsrForSubject(): CSR generation for subject ${1} failed with result code $result"
        return 2
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
            logI "genRootCaCert(): Certificate ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer already exist, nothing to do"
        else
            logI "genRootCaCert(): Generating self signed Root CA Certificate for subject ${1}"
            openssl req \
                -new \
                -key "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
                -passin pass:"${2}" \
                -x509 \
                -days ${LAB_CARTIFICATE_VALIDITY_DAYS} \
                -subj "${LAB_SUBJ_PARAM}" \
                -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
            local result=$?
            if [ "$result" -ne 0 ]; then
                logE "genRootCaCert(): Root CA self-signed certificate generation for subject ${1} failed with result code $result"
                return 3
            fi
            cat "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" > "${LAB_SUBJECTS_FOLDER}/${1}/out/public.crt.bundle.pem"
            logI "genRootCaCert(): Key ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer generated"
        fi
    fi
}

genCertForSubject(){
    # params
    # $1 - subject
    # $2 - passphrase for subject's PK
    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
        logI "genCertForSubject(): Certificate ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer already exist, nothing to do"
        return 0
    fi

    if [ -z "${2}" ]; then
        logE "genCertForSubject(): Must pass a passphrase in the second parameter"
        return 11
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/public.crt.bundle.pem" ]; then
        logE "genCertForSubject(): File not found: ${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/public.crt.bundle.pem"
        return $ERR_FS_MISSING
    fi


    # genKeysForSubject "${1}" "${2}"
    # CSR
    genCsrForSubject "${1}" "${2}"

    local pwdCA
    pwdCA=$(getPKPassForSubjectFromMemStore "${LAB_SIGNING_CA_SUBJECT_DIR}")

    logI "genCertForSubject(): Generating certificate for subject ${1}..."
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

    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "genCertForSubject(): Certificate generation for subject ${1} failed with result code $result"
        return 4
    fi

    logI "genCertForSubject(): Generating public certificate bundle for subject ${1}..."
    cat \
        "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        "${LAB_SUBJECTS_FOLDER}/${LAB_SIGNING_CA_SUBJECT_DIR}/out/public.crt.bundle.pem" \
        > "${LAB_SUBJECTS_FOLDER}/${1}/out/public.crt.bundle.pem"

    unset pwdCA

}

genKeyCertBundleForSubject(){
    # params
    # $1 - subject

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.cert.bundle.pem" ]; then
        logI "genKeyCertBundleForSubject(): Key certificate bundle file already exsts: ${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.cert.bundle.pem"
        return 0
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
        logE "genKeyCertBundleForSubject(): Private keypair file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem"
        return $ERR_FS_MISSING
    fi
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
        logE "genKeyCertBundleForSubject(): Certificte file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
        return $ERR_FS_MISSING
    fi
    logI "genKeyCertBundleForSubject(): Generating key and certificate private bundle for subject ${1}..."
    cat \
        "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        > "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.cert.bundle.pem"
}

generateP12PrivateKeyStoreForSubject(){
    # Note: 
    # for longer chains the -certfile must contain the full bundle up to the current certificate
    # excluding the one passed with -inkey

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.key.store.p12" ]; then
        logI "generateP12PrivateKeyStoreForSubject(): PKCS#12 key store for subject ${1} already exists, skipping"
        return 0
    fi

    # validations
    local validationErrors=0
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${3}/out/public.pem.cer" ]; then
        logE "generateP12PrivateKeyStoreForSubject(): CA file not found: ${LAB_SUBJECTS_FOLDER}/${3}/out/public.pem.cer"
        validationErrors=$((i+validationErrors))
    fi
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
        logE "generateP12PrivateKeyStoreForSubject(): Public certificate file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
        validationErrors=$((i+validationErrors))
    fi
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
        logE "generateP12PrivateKeyStoreForSubject(): Private keypair file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem"
        validationErrors=$((i+validationErrors))
    fi
    if [ "${validationErrors}" -ne 0 ]; then
        logE "generateP12PrivateKeyStoreForSubject(): ${} validaton errors found, cannot continue"
        return 6
    fi

    logI "generateP12PrivateKeyStoreForSubject(): Generating PKCS#12 key store without chain for subject ${1}..."
    openssl pkcs12 \
        -export \
        -in "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        -inkey "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" \
        -passin pass:"${2}" \
        -out "${LAB_SUBJECTS_FOLDER}/${1}/out/private.key.store.p12"  \
        -passout pass:"${2}" \
        -CAfile "${LAB_SUBJECTS_FOLDER}/${3}/out/public.pem.cer"
    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "generateP12PrivateKeyStoreForSubject(): Private P12 KeyStore generation for subject ${1} failed with result code $result"
        return 5
    fi
}

generateP12PrivateKeyStoreWithChainForSubject(){
    # Note: 
    # for longer chains the -certfile must contain the full bundle up to the current certificate
    # excluding the one passed with -inkey
    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/full.chain.key.store.p12" ]; then
        logI "generateP12PrivateKeyStoreWithChainForSubject(): PKCS#12 key store with chain for subject ${1} already exists, skipping"
        return 0
    fi

    # validations
    local validationErrors=0
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${3}/out/public.crt.bundle.pem" ]; then
        logE "generateP12PrivateKeyStoreWithChainForSubject(): CA bundle file not found: ${LAB_SUBJECTS_FOLDER}/${3}/out/public.crt.bundle.pem"
        validationErrors=$((i+validationErrors))
    fi
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then
        logE "generateP12PrivateKeyStoreWithChainForSubject(): Public certificate file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
        validationErrors=$((i+validationErrors))
    fi
    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem" ]; then
        logE "generateP12PrivateKeyStoreWithChainForSubject(): Private keypair file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/private.encrypted.keypair.pem"
        validationErrors=$((i+validationErrors))
    fi
    if [ "${validationErrors}" -ne 0 ]; then
        logE "generateP12PrivateKeyStoreWithChainForSubject(): ${} validaton errors found, cannot continue"
        return 7
    fi

    logI "generateP12PrivateKeyStoreWithChainForSubject(): Generate PKCS#12 key store with chain for subject ${1}..."
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

    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "generateP12PrivateKeyStoreWithChainForSubject(): Private P12 KeyStore with chain generation for subject ${1} failed with result code $result"
        return 8
    fi
}

generateP12PublicStoreForSubject(){

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.trust.store.p12" ];then
        logI "generateP12PublicStoreForSubject(): PKCS#12 trust store with chain for subject ${1} already exists"
        return 0
    fi

    openssl pkcs12 -export -nokeys \
        -in "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        -passin pass:"${2}" \
        -out "${LAB_SUBJECTS_FOLDER}/${1}/out/public.trust.store.p12" \
        -passout pass:"${2}" \
        -name "${LAB_KEY_STORE_ENTRY_NAME}"
    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "generateP12PublicStoreForSubject(): Public P12 Store generation for subject ${1} failed with result code $result"
        return 8
    fi

}

generateChainedJksForSubject(){

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/full.chain.key.store.jks" ]; then
        logI "generateChainedJksForSubject(): Subject $1 already has a jks keystore"
        return 0
    fi

    logI "generateChainedJksForSubject(): generating chain jks for subject ${1}"
    keytool -importkeystore \
        -destkeystore "${LAB_SUBJECTS_FOLDER}/${1}/out/full.chain.key.store.jks" \
        -srckeystore "${LAB_SUBJECTS_FOLDER}/${1}/out/full.chain.key.store.p12" \
        -srcalias "${LAB_KEY_STORE_ENTRY_NAME}" \
        -srcstoretype PKCS12 \
        -destalias "${LAB_KEY_STORE_ENTRY_NAME}" \
        -srcstorepass "${2}" \
        -deststorepass "${2}"
    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "generateChainedJksForSubject(): Private JKS keystore generation for subject ${1} failed with result code $result"
        return 10
    fi
}

generateSimpleTruststoreJksForSubject(){

    if [ -f "${LAB_SUBJECTS_FOLDER}/${1}/out/simple.trust.store.jks" ]; then
        logI "generateSimpleTruststoreJksForSubject(): Subject $1 already has a simple jks truststore"
        return 0
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" ]; then 
        logE "generateSimpleTruststoreJksForSubject(): Certificate file not found: ${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer"
        return $ERR_FS_MISSING
    fi

    logI "generateSimpleTruststoreJksForSubject(): importing certificate..."
    keytool -import \
        -keystore "${LAB_SUBJECTS_FOLDER}/${1}/out/simple.trust.store.jks" \
        -file "${LAB_SUBJECTS_FOLDER}/${1}/out/public.pem.cer" \
        -alias "${LAB_KEY_STORE_ENTRY_NAME}" \
        -storepass "${2}" \
        -noprompt

    local result=$?
    if [ "$result" -ne 0 ]; then
        logE "generateSimpleTruststoreJksForSubject(): Simple public JKS store generation for subject ${1} failed with result code $result"
        return 9
    fi

}

sourceSubjectLocalVars(){
    logI "sourceSubjectLocalVars(): Sourcing file ${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh"
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
            logI "assurePKPasswordForSubject(): Sourcing local env vars for subject ${1}"
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
    logI "${Cyan}====== manageSubject(): Treating subject ${Cyan}${1}${NC}"
    # validations

    if [ ! -d "${LAB_SUBJECTS_FOLDER}/${1}" ] ; then
        logE "manageSubject(): Subject folder ${LAB_SUBJECTS_FOLDER}/${1} not found!"
        return $ERR_FS_MISSING
    fi

    if [ ! -f "${LAB_SUBJECTS_FOLDER}/${1}/set_env.sh" ]; then
        logE "manageSubject(): Subject set_env.sh file missing, cannot manage this subject"
        return $ERR_FS_MISSING
    fi

    sourceSubjectLocalVars "${1}"
    # assure passphrase
    if [ -z "${LAB_PK_PASS}" ]; then
        LAB_PK_PASS=$(getPKPassForSubjectFromMemStore "${1}")
        logI "manageSubject(): LAB_PK_PASS for subject ${1} recovered from memory cache"
    else
        if [ ! -f "/dev/shm/certPasses/${1}/pass.tmp" ]; then
            mkdir -p "/dev/shm/certPasses/${1}"
            echo "${LAB_PK_PASS}" > "/dev/shm/certPasses/${1}/pass.tmp"
        fi
    fi

    mkdir -p "${LAB_SUBJECTS_FOLDER}/${1}/out"
    if [ "${LAB_SUBJECT_TYPE}" == "RootCA" ]; then
        # in case of Root CA only the self signed certificate is needed, without CSRs and the other bundled constructs
        genRootCaCert "${1}" "${LAB_PK_PASS}"
    else
        logI "manageSubject(): Managing CSR for subject ${1}"
        genCsrForSubject "${1}" "${LAB_PK_PASS}" || return $?
        logI "manageSubject(): Managing PEM Certificate stores for subject ${1}"
        genCertForSubject "${1}" "${LAB_PK_PASS}" || return $?
        genKeyCertBundleForSubject "${1}" || return $?
        logI "manageSubject(): Managing PKCS12 Certificate stores for subject ${1}"
        generateP12PrivateKeyStoreForSubject "${1}" "${LAB_PK_PASS}" "${LAB_SIGNING_CA_SUBJECT_DIR}" || return $?
        generateP12PrivateKeyStoreWithChainForSubject "${1}" "${LAB_PK_PASS}" "${LAB_SIGNING_CA_SUBJECT_DIR}" || return $?
        generateChainedJksForSubject "${1}" "${LAB_PK_PASS}" || return $?
    fi
    generateSimpleTruststoreJksForSubject "${1}" "${LAB_PK_PASS}" || return $?
    unsetSubjectLocals
}

manageAllSubjects(){
    logI "${Cyan}====== manageAllSubjects(): Treating all subjects in folder ${LAB_SUBJECTS_FOLDER}${NC}"
    oldpath=`pwd`
    cd "${LAB_SUBJECTS_FOLDER}/"
    for subjectDir in * ; do
        assurePKPasswordForSubject ${subjectDir} || logE "====== manageAllSubjects(): assurePKPasswordForSubject() exited with code $?"
        manageSubject ${subjectDir} || logE "====== manageAllSubjects(): manageSubject() exited with code $?"
    done
    cd "${oldpath}"
}