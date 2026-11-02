#!/bin/sh

validateFile()
{
    case $1 in
        *[\'!\"@\#\$%\&^*\(\),:\;]* )
            return 1;;
        *)
            return 0;;
    esac
}

validateBaseName()
{
    if [ "${1::1}" == "." ]; then
        return 1
    fi
    case $1 in
        *[\/\'!\"@\#\$%\&^*\(\),:\;]* )
            return 1;;
        *)
            return 0;;
    esac
}

validateDir()
{
    case $1 in
        *[\'!\"@\#\$%^*\(\)_+.,:\;]* )
            return 1;;
        *)
            return 0;;
    esac
}

validateLang()
{
    if [ "${#1}" != "5" ]; then
        return 1
    else
        RES=$(echo ${1} | sed -E 's/[a-zA-Z-]//g')
        if [ -z "$RES" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# Integer and float with . or ,
validateNumber(){
    case $1 in
        ''|*[!0-9.,\-]* )
            return 1;;
        * )
            return 0;;
    esac
}

# Only chars, ditigs and some special chars: '_' '-' ' '
validateString()
{
    case $1 in
        *[\'!\"@\#\$%\&^*\(\).,:\;]* )
            return 1;;
        *)
            return 0;;
    esac
}

validateQueryString()
{
    case $1 in
        *[\'!\"@\#\$%^*\(\),:\;]* )
            return 1;;
        *)
            return 0;;
    esac
}

validateKey()
{
    case $1 in
        *[\|\\\/\'!\"@\#\$%\&^*\(\).,:\;{}=?]* )
            return 1;;
        *)
            return 0;;
    esac
}

# Recording hour directory: YYYYYmmMDDDh e.g. 2024Y01M15D10H
validateRecDir()
{
    case "$1" in
        [0-9][0-9][0-9][0-9]Y[0-9][0-9]M[0-9][0-9]D[0-9][0-9]H)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# Recording clip path under record/: DIR/NNmNNsNN.mp4
validateRecFile()
{
    case "$1" in
        [0-9][0-9][0-9][0-9]Y[0-9][0-9]M[0-9][0-9]D[0-9][0-9]H/[0-9][0-9]M[0-9][0-9]S[0-9][0-9].mp4)
            return 0 ;;
        *)
            return 1 ;;
    esac
}
