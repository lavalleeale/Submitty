#!/usr/bin/env bash

# Fail the script if any command fails. If we need to capture the
# exit code of a particular command, wrap it as so:
# set +e
# some_command
# exit_code=$?
# set -e
set -e

########################################################################################################################
########################################################################################################################
# this script must be run by root or sudo
if [[ "$UID" -ne "0" ]] ; then
    echo "ERROR: This script must be run by root or sudo"
    exit 1
fi

########################################################################################################################
########################################################################################################################

# NOTE: This script is not intended to be called directly.  It is
# called from the INSTALL_SUBMITTY.sh script that is generated by
# CONFIGURE_SUBMITTY.py.  That helper script initializes dozens of
# variables that are used in the code below.

# NEW NOTE: We are now ignoring most of the variables set in the
# INSTALL_SUBMITTY.sh script, and instead re-reading them from the
# config.json files when needed.  We wait to read most variables until
# the repos are updated and the necessary migrations are run.


# We assume a relative path from this repository to the installation
# directory and configuration directory.
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SUBMITTY_REPOSITORY=$(jq -r '.submitty_repository' "${THIS_DIR}/../../../config/submitty.json")

source "${SUBMITTY_REPOSITORY}/.setup/install_submitty/get_globals.sh"



# check optional argument
if [[ "$#" -ge 1 && "$1" != "test" && "$1" != "clean" && "$1" != "test_rainbow"
       && "$1" != "skip_web_restart" && "$1" != "disable_shipper_worker" ]]; then
    echo -e "Usage:"
    echo -e "   ./INSTALL_SUBMITTY.sh"
    echo -e "   ./INSTALL_SUBMITTY.sh clean quick"
    echo -e "   ./INSTALL_SUBMITTY.sh clean test"
    echo -e "   ./INSTALL_SUBMITTY.sh clean skip_web_restart"
    echo -e "   ./INSTALL_SUBMITTY.sh clear test  <test_case_1>"
    echo -e "   ./INSTALL_SUBMITTY.sh clear test  <test_case_1> ... <test_case_n>"
    echo -e "   ./INSTALL_SUBMITTY.sh test"
    echo -e "   ./INSTALL_SUBMITTY.sh test  <test_case_1>"
    echo -e "   ./INSTALL_SUBMITTY.sh test  <test_case_1> ... <test_case_n>"
    echo -e "   ./INSTALL_SUBMITTY.sh test_rainbow"
    echo -e "   ./INSTALL_SUBMITTY.sh skip_web_restart"
    echo -e "   ./INSTALL_SUBMITTY.sh disable_shipper_worker"
    exit 1
fi

########################################################################################################################
########################################################################################################################
# FORCE CORRECT TIME SKEW
# This may happen on a development virtual machine
# SEE GITHUB ISSUE #7885 - https://github.com/Submitty/Submitty/issues/7885

if [[( "${IS_VAGRANT}" == 1  ||  "${IS_UTM}" == 1 ) &&  "${IS_CI}" == 0 ]]; then
    sudo service ntp stop
    sudo ntpd -gq
    sudo service ntp start
    sudo timedatectl set-timezone America/New_York
fi

########################################################################################################################
########################################################################################################################
# CLONE OR UPDATE THE HELPER SUBMITTY CODE REPOSITORIES

set +e
/bin/bash "${SUBMITTY_REPOSITORY}/.setup/bin/update_repos.sh"

if [ $? -eq 1 ]; then
    echo -e "\nERROR: FAILURE TO CLONE OR UPDATE SUBMITTY HELPER REPOSITORIES\n"
    echo -e "Exiting INSTALL_SUBMITTY_HELPER.sh\n"
    exit 1
fi
set -e


################################################################################################################
################################################################################################################
# RUN THE SYSTEM AND DATABASE MIGRATIONS

if [ "${IS_WORKER}" == 0 ]; then
    echo -e 'Checking for system and database migrations'

    mkdir -p "${SUBMITTY_INSTALL_DIR}/migrations"

    rsync -rtz "${SUBMITTY_REPOSITORY}/migration/migrator/migrations" "${SUBMITTY_INSTALL_DIR}"
    chown root:root "${SUBMITTY_INSTALL_DIR}/migrations"
    chmod 550 -R "${SUBMITTY_INSTALL_DIR}/migrations"

    python3 "${SUBMITTY_REPOSITORY}/migration/run_migrator.py" -e system -e master -e course migrate
fi


################################################################################################################
################################################################################################################
# VALIDATE DATABASE SUPERUSERS

if [ "${IS_WORKER}" == 0 ]; then
    DATABASE_FILE="$SUBMITTY_INSTALL_DIR/config/database.json"
    DATABASE_HOST=$(jq -r '.database_host' $DATABASE_FILE)
    DATABASE_PORT=$(jq -r '.database_port' $DATABASE_FILE)
    GLOBAL_DBUSER=$(jq -r '.database_user' $DATABASE_FILE)
    GLOBAL_DBUSER_PASS=$(jq -r '.database_password' $DATABASE_FILE)
    COURSE_DBUSER=$(jq -r '.database_course_user' $DATABASE_FILE)

    DB_CONN="-h ${DATABASE_HOST} -U ${GLOBAL_DBUSER}"
    if [ ! -d "${DATABASE_HOST}" ]; then
        DB_CONN="${DB_CONN} -p ${DATABASE_PORT}"
    fi


    CHECK=`PGPASSWORD=${GLOBAL_DBUSER_PASS} psql ${DB_CONN} -d submitty -tAc "SELECT rolsuper FROM pg_authid WHERE rolname='$GLOBAL_DBUSER'"`

    if [ "$CHECK" == "f" ]; then
        echo "ERROR: Database Superuser check failed! Master dbuser found to not be a superuser."
        exit
    fi

    CHECK=`PGPASSWORD=${GLOBAL_DBUSER_PASS} psql ${DB_CONN} -d submitty -tAc "SELECT rolsuper FROM pg_authid WHERE rolname='$COURSE_DBUSER'"`

    if [ "$CHECK" == "t" ]; then
        echo "ERROR: Database Superuser check failed! Course dbuser found to be a superuser."
        exit
    fi
fi


################################################################################################################
################################################################################################################
# INSTALL PYTHON SUBMITTY UTILS AND SET PYTHON PACKAGE PERMISSIONS

echo -e "Install python_submitty_utils"

rsync -rtz "${SUBMITTY_REPOSITORY}/python_submitty_utils" "${SUBMITTY_INSTALL_DIR}"
pushd "${SUBMITTY_INSTALL_DIR}/python_submitty_utils"

pip3 install .
# Setting the permissions are necessary as pip uses the umask of the user/system, which
# affects the other permissions (which ideally should be o+rx, but Submitty sets it to o-rwx).
# This gets run here in case we make any python package changes.
find /usr/local/lib/python*/dist-packages -type d -exec chmod 755 {} +
find /usr/local/lib/python*/dist-packages -type f -exec chmod 755 {} +
find /usr/local/lib/python*/dist-packages -type f -name '*.py*' -exec chmod 644 {} +
find /usr/local/lib/python*/dist-packages -type f -name '*.pth' -exec chmod 644 {} +

popd > /dev/null


########################################################################################################################
########################################################################################################################

echo -e "\nBeginning installation of Submitty\n"

/bin/bash "${SUBMITTY_REPOSITORY}/.setup/install_submitty/setup_directories.sh" "$@"

########################################################################################################################
########################################################################################################################
# RSYNC NOTES
#  a = archive, recurse through directories, preserves file permissions, owner  [ NOT USED, DON'T WANT TO MESS W/ PERMISSIONS ]
#  r = recursive
#  v = verbose, what was actually copied
#  t = preserve modification times
#  u = only copy things that have changed
#  z = compresses (faster for text, maybe not for binary)
#  (--delete, but probably dont want)
#  / trailing slash, copies contents into target
#  no slash, copies the directory & contents to target

########################################################################################################################
########################################################################################################################
# CHECKOUT & INSTALL THE NLOHMANN C++ JSON LIBRARY

nlohmann_dir="${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/vendor/nlohmann/json"

# If we don't already have a copy of this repository, check it out
if [ ! -d "${nlohmann_dir}" ]; then
    git clone --depth 1 "https://github.com/nlohmann/json.git" "${nlohmann_dir}"
fi

# TODO: We aren't checking / enforcing a specific/minimum version of this library...

# Add read & traverse permissions for RainbowGrades and vendor repos
find "${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/vendor" -type d -exec chmod o+rx {} \;
find "${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/vendor" -type f -exec chmod o+r {} \;

# "install" the nlohmann json library
mkdir -p "${SUBMITTY_INSTALL_DIR}/vendor"
sudo chown -R root:submitty_course_builders "${SUBMITTY_INSTALL_DIR}/vendor"
sudo chown -R root:submitty_course_builders "${SUBMITTY_INSTALL_DIR}/vendor"
rsync -rtz "${SUBMITTY_REPOSITORY}/../vendor/nlohmann/json/include" "${SUBMITTY_INSTALL_DIR}/vendor/"
chown -R  root:root "${SUBMITTY_INSTALL_DIR}/vendor"
find "${SUBMITTY_INSTALL_DIR}/vendor" -type d -exec chmod 555 {} \;
find "${SUBMITTY_INSTALL_DIR}/vendor" -type f -exec chmod 444 {} \;


########################################################################################################################
########################################################################################################################
# COPY THE CORE GRADING CODE (C++ files) & BUILD THE SUBMITTY GRADING LIBRARY

echo -e "Copy the grading code"

# copy the files from the repo
rsync -rtz "${SUBMITTY_REPOSITORY}/grading" "${SUBMITTY_INSTALL_DIR}/src"

# copy the allowed_autograding_commands_default.json to config
rsync -tz "${SUBMITTY_REPOSITORY}/grading/allowed_autograding_commands_default.json" "${SUBMITTY_INSTALL_DIR}/config"

# replace filling variables
sed -i -e "s|__INSTALL__FILLIN__SUBMITTY_INSTALL_DIR__|$SUBMITTY_INSTALL_DIR|g" "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_default.json"

# # change permissions of allowed_autograding_commands_default.json
chown "root":"root" "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_default.json"
chmod 644 "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_default.json"

# create allowed_autograding_commands_custom.json if doesnt exist
if [[ ! -e "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_custom.json" ]]; then
    rsync -tz "${SUBMITTY_REPOSITORY}/grading/allowed_autograding_commands_custom.json" "${SUBMITTY_INSTALL_DIR}/config"
fi

# replace filling variables
sed -i -e "s|__INSTALL__FILLIN__SUBMITTY_INSTALL_DIR__|$SUBMITTY_INSTALL_DIR|g" "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_custom.json"

# # change permissions of allowed_autograding_commands_custom.json
chown "root":"root" "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_custom.json"
chmod 644 "${SUBMITTY_INSTALL_DIR}/config/allowed_autograding_commands_custom.json"

#replace necessary variables
array=( Sample_CMakeLists.txt CMakeLists.txt system_call_check.cpp seccomp_functions.cpp execute.cpp )
for i in "${array[@]}"; do
    replace_fillin_variables "${SUBMITTY_INSTALL_DIR}/src/grading/${i}"
done

# building the autograding library
mkdir -p "${SUBMITTY_INSTALL_DIR}/src/grading/lib"
pushd "${SUBMITTY_INSTALL_DIR}/src/grading/lib"
cmake ..
set +e
make
if [ "$?" -ne 0 ] ; then
    echo "ERROR BUILDING AUTOGRADING LIBRARY"
    exit 1
fi
set -e
popd > /dev/null

# root will be owner & group of these files
chown -R  root:root "${SUBMITTY_INSTALL_DIR}/src"
# "other" can cd into & ls all subdirectories
find "${SUBMITTY_INSTALL_DIR}/src" -type d -exec chmod 555 {} \;
# "other" can read all files
find "${SUBMITTY_INSTALL_DIR}/src" -type f -exec chmod 444 {} \;

chgrp submitty_daemon "${SUBMITTY_INSTALL_DIR}/src/grading/python/submitty_router.py"
chmod g+wrx           "${SUBMITTY_INSTALL_DIR}/src/grading/python/submitty_router.py"


#Set up sample files if not in worker mode.
if [ "${IS_WORKER}" == 0 ]; then
    ########################################################################################################################
    ########################################################################################################################
    # COPY THE SAMPLE FILES FOR COURSE MANAGEMENT

    echo -e "Copy the sample files"

    # copy the files from the repo
    rsync -rtz "${SUBMITTY_REPOSITORY}/more_autograding_examples" "${SUBMITTY_INSTALL_DIR}"

    # root will be owner & group of these files
    chown -R  root:root "${SUBMITTY_INSTALL_DIR}/more_autograding_examples"
    # but everyone can read all that files & directories, and cd into all the directories
    find "${SUBMITTY_INSTALL_DIR}/more_autograding_examples" -type d -exec chmod 555 {} \;
    find "${SUBMITTY_INSTALL_DIR}/more_autograding_examples" -type f -exec chmod 444 {} \;
fi
########################################################################################################################
########################################################################################################################
# BUILD JUNIT TEST RUNNER (.java file) if Java is installed on the machine

if [ -x "$(command -v javac)" ] &&
   [ -d ${SUBMITTY_INSTALL_DIR}/java_tools/JUnit ]; then
    echo -e "Build the junit test runner"

    # copy the file from the repo
    rsync -rtz "${SUBMITTY_REPOSITORY}/junit_test_runner/TestRunner.java" "${SUBMITTY_INSTALL_DIR}/java_tools/JUnit/TestRunner.java"

    pushd "${SUBMITTY_INSTALL_DIR}/java_tools/JUnit" > /dev/null
    # root will be owner & group of the source file
    chown  root:root  TestRunner.java
    # everyone can read this file
    chmod  444 TestRunner.java

    # compile the executable using the javac we use in the execute.cpp safelist
    /usr/bin/javac -cp ./junit-4.12.jar TestRunner.java

    # everyone can read the compiled file
    chown root:root TestRunner.class
    chmod 444 TestRunner.class

    popd > /dev/null


    # fix all java_tools permissions
    chown -R "root:${COURSE_BUILDERS_GROUP}" "${SUBMITTY_INSTALL_DIR}/java_tools"
    chmod -R 755                             "${SUBMITTY_INSTALL_DIR}/java_tools"
else
    echo -e "Skipping build of the junit test runner"
fi


#################################################################
# DRMEMORY SETUP
#################

# Dr Memory is a tool for detecting memory errors in C++ programs (similar to Valgrind)

# FIXME: Use of this tool should eventually be moved to containerized
# autograding and not installed on the native primary and worker
# machines by default

# FIXME: DrMemory is initially installed in install_system.sh
# It is re-installed here (on every Submitty software update) in case of version updates.

pushd /tmp > /dev/null

echo "Updating DrMemory..."

rm -rf /tmp/DrMemory*
wget https://github.com/DynamoRIO/drmemory/releases/download/${DRMEMORY_TAG}/DrMemory-Linux-${DRMEMORY_VERSION}.tar.gz -o /dev/null > /dev/null 2>&1
tar -xpzf DrMemory-Linux-${DRMEMORY_VERSION}.tar.gz
rsync --delete -a /tmp/DrMemory-Linux-${DRMEMORY_VERSION}/ ${SUBMITTY_INSTALL_DIR}/drmemory
rm -rf /tmp/DrMemory*

chown -R root:${COURSE_BUILDERS_GROUP} ${SUBMITTY_INSTALL_DIR}/drmemory
chmod -R 755 ${SUBMITTY_INSTALL_DIR}/drmemory



echo "...DrMemory ${DRMEMORY_TAG} update complete."

popd > /dev/null


########################################################################################################################
########################################################################################################################
# COPY VARIOUS SCRIPTS USED BY INSTRUCTORS AND SYS ADMINS FOR COURSE ADMINISTRATION

bash "${SUBMITTY_REPOSITORY}/.setup/install_submitty/install_bin.sh"

# build the helper program for strace output and restrictions by system call categories
g++ "${SUBMITTY_INSTALL_DIR}/src/grading/system_call_check.cpp" -o "${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out"

# build the helper program for calculating early submission incentive extensions
g++ "${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.cpp" -lboost_system -lboost_filesystem -std=c++11 -Wall -g -o "${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out"

GRADINGCODE="${SUBMITTY_INSTALL_DIR}/src/grading"
JSONCODE="${SUBMITTY_INSTALL_DIR}/vendor/include"

# Create the complete/build config using main_configure
g++ "${GRADINGCODE}/main_configure.cpp" \
    "${GRADINGCODE}/load_config_json.cpp" \
    "${GRADINGCODE}/execute.cpp" \
    "${GRADINGCODE}/TestCase.cpp" \
    "${GRADINGCODE}/error_message.cpp" \
    "${GRADINGCODE}/window_utils.cpp" \
    "${GRADINGCODE}/dispatch.cpp" \
    "${GRADINGCODE}/change.cpp" \
    "${GRADINGCODE}/difference.cpp" \
    "${GRADINGCODE}/tokenSearch.cpp" \
    "${GRADINGCODE}/tokens.cpp" \
    "${GRADINGCODE}/clean.cpp" \
    "${GRADINGCODE}/execute_limits.cpp" \
    "${GRADINGCODE}/seccomp_functions.cpp" \
    "${GRADINGCODE}/empty_custom_function.cpp" \
    "${GRADINGCODE}/allowed_autograding_commands.cpp" \
    "-I${JSONCODE}" \
    -pthread -std=c++11 -lseccomp -o "${SUBMITTY_INSTALL_DIR}/bin/configure.out"

# set the permissions
chown "root:${COURSE_BUILDERS_GROUP}" "${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out"
chmod 550                             "${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out"

chown "root:${COURSE_BUILDERS_GROUP}" "${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out"
chmod 550                             "${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out"

chown ${DAEMON_USER}:${COURSE_BUILDERS_GROUP} "${SUBMITTY_INSTALL_DIR}/bin/configure.out"
chmod 550 ${SUBMITTY_INSTALL_DIR}/bin/configure.out


###############################################
# scripts used only by root for setup only
mkdir -p        "${SUBMITTY_INSTALL_DIR}/.setup/bin"
chown root:root "${SUBMITTY_INSTALL_DIR}/.setup/bin"
chmod 700       "${SUBMITTY_INSTALL_DIR}/.setup/bin"

cp  "${SUBMITTY_REPOSITORY}/.setup/bin/reupload_old_assignments.py" "${SUBMITTY_INSTALL_DIR}/.setup/bin/"
cp  "${SUBMITTY_REPOSITORY}/.setup/bin/reupload_generate_csv.py"    "${SUBMITTY_INSTALL_DIR}/.setup/bin/"
cp  "${SUBMITTY_REPOSITORY}/.setup/bin/track_git_version.py"        "${SUBMITTY_INSTALL_DIR}/.setup/bin/"
cp  "${SUBMITTY_REPOSITORY}/.setup/bin/init_auto_rainbow.py"        "${SUBMITTY_INSTALL_DIR}/.setup/bin/"
chown root:root "${SUBMITTY_INSTALL_DIR}/.setup/bin/reupload"*
chmod 700       "${SUBMITTY_INSTALL_DIR}/.setup/bin/reupload"*
chown root:root "${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py"
chmod 700       "${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py"

###############################################
# submitty_test script
cp  "${SUBMITTY_REPOSITORY}/.setup/SUBMITTY_TEST.sh"        "${SUBMITTY_INSTALL_DIR}/.setup/"
chown root:root "${SUBMITTY_INSTALL_DIR}/.setup/SUBMITTY_TEST.sh"
chmod 700       "${SUBMITTY_INSTALL_DIR}/.setup/SUBMITTY_TEST.sh"

########################################################################################################################
########################################################################################################################
# PREPARE THE UNTRUSTED_EXEUCTE EXECUTABLE WITH SUID

# copy the file
rsync -rtz  "${SUBMITTY_REPOSITORY}/.setup/untrusted_execute.c"   "${SUBMITTY_INSTALL_DIR}/.setup/"
# replace necessary variables
replace_fillin_variables "${SUBMITTY_INSTALL_DIR}/.setup/untrusted_execute.c"

# SUID (Set owner User ID up on execution), allows the $DAEMON_USER
# to run this executable as sudo/root, which is necessary for the
# "switch user" to untrusted as part of the sandbox.

pushd "${SUBMITTY_INSTALL_DIR}/.setup/" > /dev/null
# set ownership/permissions on the source code
chown root:root untrusted_execute.c
chmod 500 untrusted_execute.c
# compile the code
g++ -static untrusted_execute.c -o "${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute"
# change permissions & set suid: (must be root)
chown root           "${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute"
chgrp "$DAEMON_USER" "${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute"
chmod 4550           "${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute"
popd > /dev/null


################################################################################################################
################################################################################################################
# COPY THE 1.0 Grading Website if not in worker mode
if [ "${IS_WORKER}" == 0 ]; then
    bash "${SUBMITTY_REPOSITORY}/.setup/install_submitty/install_site.sh" browscap
fi

################################################################################################################
################################################################################################################
# COMPILE AND INSTALL ANALYSIS TOOLS

echo -e "Compile and install analysis tools"

mkdir -p "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"

pushd "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
if [[ ! -f VERSION || $(< VERSION) != "${AnalysisTools_Version}" ]]; then
    for b in count plagiarism diagnostics;
        do wget -nv "https://github.com/Submitty/AnalysisTools/releases/download/${AnalysisTools_Version}/${b}" -O ${b}
    done

    echo "${AnalysisTools_Version}" > VERSION
fi
popd > /dev/null

# change permissions
chown -R "${DAEMON_USER}:${COURSE_BUILDERS_GROUP}" "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
chmod -R 555                                       "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"

# NOTE: These variables must match the same variables in install_system.sh
clangsrc="${SUBMITTY_INSTALL_DIR}/clang-llvm/src"
clangbuild="${SUBMITTY_INSTALL_DIR}/clang-llvm/build"
# note, we are not running 'ninja install', so this path is unused.
clanginstall="${SUBMITTY_INSTALL_DIR}/clang-llvm/install"

ANALYSIS_TOOLS_REPO="${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/AnalysisTools"

# copying commonAST scripts
mkdir -p "${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/"
mkdir -p "${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/"

array=( astMatcher.py commonast.py unionToolRunner.py jsonDiff.py utils.py refMaps.py match.py eqTag.py context.py \
        removeTokens.py jsonDiffSubmittyRunner.py jsonDiffRunner.py jsonDiffRunnerRunner.py createAllJson.py )
for i in "${array[@]}"; do
    rsync -rtz "${ANALYSIS_TOOLS_REPO}/commonAST/${i}" "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
done

rsync -rtz "${ANALYSIS_TOOLS_REPO}/commonAST/unionTool.cpp"       "${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/"
rsync -rtz "${ANALYSIS_TOOLS_REPO}/commonAST/CMakeLists.txt"      "${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/"
rsync -rtz "${ANALYSIS_TOOLS_REPO}/commonAST/ASTMatcher.cpp"      "${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/"
rsync -rtz "${ANALYSIS_TOOLS_REPO}/commonAST/CMakeListsUnion.txt" "${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/CMakeLists.txt"

#copying tree visualization scrips
rsync -rtz "${ANALYSIS_TOOLS_REPO}/treeTool/make_tree_interactive.py" "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
rsync -rtz "${ANALYSIS_TOOLS_REPO}/treeTool/treeTemplate1.txt"        "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
rsync -rtz "${ANALYSIS_TOOLS_REPO}/treeTool/treeTemplate2.txt"        "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"

#building commonAST excecutable
pushd "${ANALYSIS_TOOLS_REPO}"
g++ commonAST/parser.cpp commonAST/traversal.cpp -o "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/commonASTCount.out"
g++ commonAST/parserUnion.cpp commonAST/traversalUnion.cpp -o "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/unionCount.out"
popd > /dev/null

# FIXME: skipping this step as it has errors, and we don't use the output of it yet

# building clang ASTMatcher.cpp
# mkdir -p ${clanginstall}
# mkdir -p ${clangbuild}
# pushd ${clangbuild}
# TODO: this cmake only needs to be done the first time...  could optimize commands later if slow?
# cmake .
#ninja ASTMatcher UnionTool
# popd > /dev/null

# cp ${clangbuild}/bin/ASTMatcher ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/
# cp ${clangbuild}/bin/UnionTool ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/
# chmod o+rx ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/ASTMatcher
# chmod o+rx ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/UnionTool


# change permissions
chown -R "${DAEMON_USER}:${COURSE_BUILDERS_GROUP}" "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"
chmod -R 555 "${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools"

################################################################################################################
################################################################################################################
# BUILD AND INSTALL ANALYSIS TOOLS TS

echo -e "Build and install analysis tools ts"

ANALYSIS_TOOLS_TS_REPO="${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/AnalysisToolsTS/"

# # build project
/bin/bash "${ANALYSIS_TOOLS_TS_REPO}/install_analysistoolsts.sh"

#####################################
# Add read & traverse permissions for RainbowGrades and vendor repos

find "${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/RainbowGrades" -type d -exec chmod o+rx {} \;
find "${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/RainbowGrades" -type f -exec chmod o+r {} \;

#####################################
# Obtain API auth token for submitty-admin user
if [ "${IS_WORKER}" == 0 ]; then
    python3 "${SUBMITTY_INSTALL_DIR}/.setup/bin/init_auto_rainbow.py"
fi
#####################################
# Build & Install Lichen Modules

/bin/bash "${SUBMITTY_REPOSITORY}/../Lichen/install_lichen.sh"


################################################################################################################
################################################################################################################

# Obtains the current git hash and tag and stores them in the appropriate jsons.
python3 "${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py"
chmod o+r "${SUBMITTY_INSTALL_DIR}/config/version.json"

installed_commit=$(jq '.installed_commit' /usr/local/submitty/config/version.json)
most_recent_git_tag=$(jq '.most_recent_git_tag' /usr/local/submitty/config/version.json)
echo -e "Completed installation of the Submitty version ${most_recent_git_tag//\"/}, commit ${installed_commit//\"/}\n"

################################################################################################################
################################################################################################################
# INSTALL SUBMITTY CRONTAB
#############################################################

cat "${SUBMITTY_REPOSITORY}/.setup/submitty_crontab" | envsubst | cat - > "/etc/cron.d/submitty"

################################################################################################################
################################################################################################################
# Allow course creation by daemon
#############################################################

cat "${SUBMITTY_REPOSITORY}/.setup/submitty_sudoers" | envsubst | cat - > /etc/sudoers.d/submitty
chmod 0440 /etc/sudoers.d/submitty
chown root:root /etc/sudoers.d/submitty

################################################################################################################
################################################################################################################
# INSTALL & START GRADING SCHEDULER DAEMON
#############################################################
# stop the submitty daemons (if they're running)
for i in "${ALL_DAEMONS[@]}"; do
    set +e
    systemctl is-active --quiet "${i}"
    is_active_now="$?"
    set -e
    if [[ "${is_active_now}" == "0" ]]; then
        systemctl stop "${i}"
        echo -e "Stopped ${i}"
    fi
    set +e
    systemctl is-active --quiet "${i}"
    is_active_tmp="$?"
    set -e
    if [[ "$is_active_tmp" == "0" ]]; then
        echo -e "ERROR: did not successfully stop {$i}\n"
        exit 1
    fi
done

if [ "${IS_WORKER}" == 0 ]; then
    # Stop all workers on remote machines
    echo -e -n "Stopping all remote machine workers...\n"
    sudo -H -u "${DAEMON_USER}" python3 "${SUBMITTY_INSTALL_DIR}/sbin/shipper_utils/systemctl_wrapper.py" stop --target perform_on_all_workers
    echo -e "done"
fi

# force kill any other shipper processes that may be manually running on the primary machine
if [ "${IS_WORKER}" == 0 ]; then
    for i in $(ps -ef | grep submitty_autograding_shipper | grep -v grep | awk '{print $2}'); do
        echo "ERROR: Also kill shipper pid $i";
        kill "$i" || true;
    done
fi

# force kill any other worker processes that may be manually running on the primary or remote machines
for i in $(ps -ef | grep submitty_autograding_worker | grep -v grep | awk '{print $2}'); do
    echo "ERROR: Also kill shipper pid $i";
    kill "$i" || true;
done


#############################################################
# cleanup the TODO and DONE folders
original_autograding_workers=/var/local/submitty/autograding_TODO/autograding_worker.json
if [ -f $original_autograding_workers ]; then
    temp_autograding_workers=`mktemp`
    echo "save this file! ${original_autograding_workers} ${temp_autograding_workers}"
    mv "${original_autograding_workers}" "${temp_autograding_workers}"
fi

array=( autograding_TODO autograding_DONE )
for i in "${array[@]}"; do
    rm -rf "${SUBMITTY_DATA_DIR}/${i}"
    mkdir -p "${SUBMITTY_DATA_DIR}/${i}"
    chown -R "${DAEMON_USER}:${DAEMON_GID}" "${SUBMITTY_DATA_DIR}/${i}"
    chmod 770 "${SUBMITTY_DATA_DIR}/${i}"
done

# return the autograding_workers json
if [ -f "$temp_autograding_workers" ]; then
    echo "return this file! ${temp_autograding_workers} ${original_autograding_workers}"
    mv "${temp_autograding_workers}" "${original_autograding_workers}"
fi

#############################################################
# update the various daemons

for i in "${ALL_DAEMONS[@]}"; do
    # update the autograding shipper & worker daemons
    rsync -rtz  "${SUBMITTY_REPOSITORY}/.setup/${i}.service" "/etc/systemd/system/${i}.service"
    chown -R "${DAEMON_USER}:${DAEMON_GROUP}"                "/etc/systemd/system/${i}.service"
    chmod 444                                                "/etc/systemd/system/${i}.service"
done

# delete the autograding tmp directories
rm -rf /var/local/submitty/autograding_tmp

# recreate the top level autograding tmp directory
mkdir /var/local/submitty/autograding_tmp
chown root:root /var/local/submitty/autograding_tmp
chmod 511 /var/local/submitty/autograding_tmp

# recreate the per untrusted directories
for ((i=0;i<$NUM_UNTRUSTED;i++));
do
    myuser=`printf "untrusted%02d" $i`
    mydir=`printf "/var/local/submitty/autograding_tmp/untrusted%02d" $i`
    mkdir "$mydir"
    chown "${DAEMON_USER}:$myuser" "$mydir"
    chmod 770 "$mydir"
done


#############################################################################
# Cleanup Old Email

# Will scan the emails table in the main Submitty database for email
# receipts that were successfully sent at least 360 days ago, with no
# errors, and delete them from the table.  A maximum of 10,000 email
# receipts will be deleted.
if [ "${IS_WORKER}" == 0 ]; then
    "${SUBMITTY_INSTALL_DIR}/sbin/cleanup_old_email.py" 360 10000
fi

#############################################################################
# Delete expired sessions

# Deletes all expired sessions from the main Submitty database
if [ "${IS_WORKER}" == 0 ]; then
    "${SUBMITTY_INSTALL_DIR}/sbin/delete_expired_sessions.py"
fi

#############################################################################
# If the migrations have indicated that it is necessary to rebuild all
# existing gradeables, do so.

REBUILD_ALL_FILENAME="${SUBMITTY_INSTALL_DIR}/REBUILD_ALL_FLAG.txt"

if [ -f "$REBUILD_ALL_FILENAME" ]; then
    echo -e "\n\nMigration has indicated that the code includes a breaking change for autograding"
    echo -e "\n\nMust rebuild ALL GRADEABLES\n\n"
    for s in /var/local/submitty/courses/*/*; do c=`basename "$s"`; "${s}/BUILD_${c}.sh" --clean; done
    echo -e "\n\nDone rebuilding ALL GRADEABLES for ALL COURSES\n\n"
    rm "$REBUILD_ALL_FILENAME"
fi

#############################################################################

# Restart php-fpm and apache
if [ "${IS_WORKER}" == 0 ]; then
    if [[ "$#" == 0 || ("$#" == 1 && "$1" != "skip_web_restart") || ("$#" -ge 2  && ("$1" != "skip_web_restart" && "$2" != "skip_web_restart")) ]]; then
        PHP_VERSION=$(php -r 'print PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
        echo -n "restarting php${PHP_VERSION}-fpm..."
        systemctl restart "php${PHP_VERSION}-fpm"
        echo "done"
        echo -n "restarting apache2..."
        systemctl restart apache2
        echo "done"
        echo -n "restarting nginx..."
        systemctl restart nginx
        echo "done"
    fi
fi


# If any of our daemon files have changed, we should reload the units:
systemctl daemon-reload

# restart the socket & jobs handler daemons
for i in "${RESTART_DAEMONS[@]}"; do
    systemctl restart "${i}"
    set +e
    systemctl is-active --quiet "${i}"
    is_active_after="$?"
    set -e
    if [[ "$is_active_after" != "0" ]]; then
        echo -e "\nERROR!  Failed to restart ${i}\n"
    else
        echo -e "Restarted ${i}"
    fi
done

################################################################################################################
################################################################################################################
# INSTALL TEST SUITE if not in worker mode
if [ "${IS_WORKER}" == 0 ]; then
    # one optional argument installs & runs test suite
    if [[ "$#" -ge 1 && "$1" == "test" ]]; then

        # copy the directory tree and replace variables
        echo -e "Install Autograding Test Suite..."
        rsync -rtz  "${SUBMITTY_REPOSITORY}/tests/"  "${SUBMITTY_INSTALL_DIR}/test_suite"
        mkdir -p "${SUBMITTY_INSTALL_DIR}/test_suite/log"

        # add a symlink to conveniently run the test suite or specific tests without the full reinstall
        ln -sf  "${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py"  "${SUBMITTY_INSTALL_DIR}/sbin/run_test_suite.py"

        echo -e "\nRun Autograding Test Suite...\n"

        # pop the first argument from the list of command args
        shift
        # pass any additional command line arguments to the run test suite
        python3 "${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py" "$@"

        echo -e "\nCompleted Autograding Test Suite\n"
    fi
fi

################################################################################################################
################################################################################################################

# INSTALL RAINBOW GRADES TEST SUITE if not in worker mode
if [ "${IS_WORKER}" == 0 ]; then
    # one optional argument installs & runs test suite
    if [[ "$#" -ge 1 && "$1" == "test_rainbow" ]]; then

        # copy the directory tree and replace variables
        echo -e "Install Rainbow Grades Test Suite..."
        rsync -rtz "${SUBMITTY_REPOSITORY}/tests/"  "${SUBMITTY_INSTALL_DIR}/test_suite"

        # add a symlink to conveniently run the test suite or specific tests without the full reinstall
        #ln -sf  ${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py  ${SUBMITTY_INSTALL_DIR}/bin/run_test_suite.py

        echo -e "\nRun Rainbow Grades Test Suite...\n"
        rainbow_counter=0
        rainbow_total=0

        # pop the first argument from the list of command args
        shift
        # pass any additional command line arguments to the run test suite
        rainbow_total=$((rainbow_total+1))
        set +e
        python3 "${SUBMITTY_INSTALL_DIR}/test_suite/rainbowGrades/test_sample.py"  "$@"

        if [[ "$?" -ne 0 ]]; then
            echo -e "\n[ FAILED ] sample test\n"
        else
            rainbow_counter=$((rainbow_counter+1))
            echo -e "\n[ SUCCEEDED ] sample test\n"
        fi
        set -e

        echo -e "\nCompleted Rainbow Grades Test Suite. $rainbow_counter of $rainbow_total tests succeeded.\n"
    fi
fi

################################################################################################################
################################################################################################################
# confirm permissions on the repository (to allow push updates from primary to worker)
if [ "${IS_WORKER}" == 1 ]; then
    # the supervisor user/group must have write access on the worker machine
    echo -e -n "Update/confirm worker repository permissions"
    chgrp -R "${SUPERVISOR_USER}" "${SUBMITTY_REPOSITORY}"
    chmod -R g+rw "${SUBMITTY_REPOSITORY}"
else
    if [ "${IS_VAGRANT}" == 0 ]; then
        # in order to update the submitty source files on the worker machines
        # the DAEMON_USER/DAEMON_GROUP must have read access to the repo on the primary machine
        echo -e -n "Update/confirm primary repository permissions"
        chgrp -R "${DAEMON_GID}" "${SUBMITTY_REPOSITORY}"
        chmod -R g+r "${SUBMITTY_REPOSITORY}"
    fi

    # Update any foreign worker machines
    echo -e -n "Update worker machines software and install docker images on all machines\n\n"
    # note: unbuffer the output (python3 -u), since installing docker images takes a while
    #       and we'd like to watch the progress
    sudo -H -u "${DAEMON_USER}" python3 -u "${SUBMITTY_INSTALL_DIR}/sbin/shipper_utils/update_and_install_workers.py"
    echo -e -n "Done updating workers and installing docker images\n\n"

    if [[ "$#" -ge 1 && "$1" == "disable_shipper_worker" ]]; then
        echo -e -n "WARNING: Autograding shipper and worker are disabled\n\n"
    else
        # Restart the shipper & workers
        echo -e -n "Restart shipper & workers\n\n"
        python3 -u "${SUBMITTY_INSTALL_DIR}/sbin/restart_shipper_and_all_workers.py"
        echo -e -n "Done restarting shipper & workers\n\n"
    fi

    # Dispatch daemon job to update OS info
    chown "root:${DAEMON_USER}" "${SUBMITTY_INSTALL_DIR}/sbin/update_worker_sysinfo.sh"
    chmod 750 "${SUBMITTY_INSTALL_DIR}/sbin/update_worker_sysinfo.sh"
    "${SUBMITTY_INSTALL_DIR}/sbin/update_worker_sysinfo.sh" UpdateDockerImages
    "${SUBMITTY_INSTALL_DIR}/sbin/update_worker_sysinfo.sh" UpdateSystemInfo
fi
