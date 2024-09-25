#!/usr/bin/env bash
# Define colors
has_colors() {
    local has_colors=false
    if [ -t 1 ]; then
        if command -v tput >/dev/null 2>&1; then
            if [ "$TERM" != linux ]; then
                has_colors=true
            fi
        fi
    fi
    echo $has_colors
}

if $(has_colors); then
    # Use color codes
    DEFAULT_COLOR="\033[0m"
    GREEN_COLOR="\033[0;32m"
    RED_COLOR="\033[0;31m"
else
    # Don't use color codes
    DEFAULT_COLOR=""
    GREEN_COLOR=""
    RED_COLOR=""
fi

version_greater_than_or_equal() {
  local version1="$1"
  local version2="$2"

  local v1=(${version1//./ })
  local v2=(${version2//./ })

  for ((i=0; i<${#v1[@]} || i<${#v2[@]}; i++)); do
    local v1_part=${v1[i]-0}
    local v2_part=${v2[i]-0}

    if (( v1_part > v2_part )); then
      return 0
    elif (( v1_part < v2_part )); then
      return 1
    fi
  done

  return 0
}

# Check CDK version
cdk_version=$(cdk --version | cut -d' ' -f1)
required_version="2.160.0"

if ! version_greater_than_or_equal "$cdk_version" "$required_version"; then
  # The CDK version is less than the required version
  echo -e "${RED_COLOR}Error: Your CDK version ($cdk_version) is outdated. Please upgrade to $required_version or later.${DEFAULT_COLOR}"
  echo -e "${GREEN_COLOR}To upgrade, run the following commands:${DEFAULT_COLOR}"
  echo -e "${GREEN_COLOR}npm uninstall -g aws-cdk${DEFAULT_COLOR}"
  echo -e "${GREEN_COLOR}npm install -g aws-cdk@latest${DEFAULT_COLOR}"
  echo -e " "
  echo -e "${DEFAULT_COLOR}or if you get permission errors, try these commands:${DEFAULT_COLOR}"
  echo -e " "
  echo -e "${GREEN_COLOR}sudo npm uninstall -g aws-cdk${DEFAULT_COLOR}"
  echo -e "${GREEN_COLOR}sudo npm install -g aws-cdk@latest${DEFAULT_COLOR}"
  exit 1
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--app) app_flag="--app $2"; shift 2;;
        -c|--context) context_flag="--context $2"; shift 2;;
        --debug) debug_flag="--debug"; shift;;
        --profile) profile_flag="--profile $2"; shift 2;;
        -t|--tags) tags_flag="--tags $2"; shift 2;;
        -f|--force) force_flag="--force"; shift;;
        -v|--verbose) verbose_flag="--verbose"; shift;;
        -r|--role-arn) role_arn_flag="--role-arn $2"; shift 2;;
        *) echo "Unknown argument: $1"; shift;;
    esac
done

# Check if AWS CDK is installed
if ! command -v cdk &> /dev/null
then
    echo -e "${RED_COLOR}Error: AWS CDK is not installed. Please install the AWS CDK or run the setup script.${DEFAULT_COLOR}"
    echo -e "${GREEN_COLOR}To install the AWS CDK manually, follow the instructions at: https://docs.aws.amazon.com/cdk/latest/guide/getting_started.html${DEFAULT_COLOR}"
    echo -e "${GREEN_COLOR}Alternatively, you can run the setup script by executing: ./setup.sh${DEFAULT_COLOR}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo -e "${RED_COLOR}Error: jq is not installed. Please install jq and try again.${DEFAULT_COLOR}"
    case "$(uname -s)" in
        Linux*) echo -e "${GREEN_COLOR}On Linux, you can install jq with: sudo apt-get install jq${DEFAULT_COLOR}" ;;
        Darwin*) echo -e "${GREEN_COLOR}On macOS, you can install jq with: brew install jq${DEFAULT_COLOR}" ;; 
        CYGWIN*|MINGW*|MSYS*) echo -e "${GREEN_COLOR}On Windows with PowerShell, you can install jq with: choco install jq${DEFAULT_COLOR}" ;;
        *) echo -e "${RED_COLOR}Unsupported operating system. Please install jq manually.${DEFAULT_COLOR}" ;;
    esac
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null
then
    echo -e "${RED_COLOR}Error: AWS CLI is not installed. Please install the AWS CLI and configure your AWS credentials before running this script.${DEFAULT_COLOR}"
    case "$(uname -s)" in
        Linux*) echo -e "${GREEN_COLOR}On Linux, you can install the AWS CLI with: sudo apt-get install awscli${DEFAULT_COLOR}" ;;
        Darwin*) echo -e "${GREEN_COLOR}On macOS, you can install the AWS CLI with: brew install awscli${DEFAULT_COLOR}" ;;
        CYGWIN*|MINGW*|MSYS*) echo -e "${GREEN_COLOR}On Windows, you can download and install the AWS CLI from: https://aws.amazon.com/cli/${DEFAULT_COLOR}" ;;
        *) echo -e "${RED_COLOR}Unsupported operating system. Please visit https://aws.amazon.com/cli/ for installation instructions.${DEFAULT_COLOR}" ;;
    esac
    echo -e "${GREEN_COLOR}After installing the AWS CLI, run 'aws configure' to set up your AWS credentials.${DEFAULT_COLOR}"
    echo -e "${GREEN_COLOR}Visit https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html for more information.${DEFAULT_COLOR}"
    exit 1
fi

# Check if the virtual environment is activated
if [ -z "${VIRTUAL_ENV}" ]; then
    # Virtual environment is not activated
    if [ -d "./cdk/.venv" ]; then
        # Virtual environment exists, but not activated
        echo -e "${DEFAULT_COLOR}The virtual environment exists but is not activated."
        echo -e "${DEFAULT_COLOR}To activate the virtual environment, run the following commands:"
        echo -e ""
        echo -e "${GREEN_COLOR}cd cdk"
        echo -e "${GREEN_COLOR}source .venv/bin/activate"
        echo -e "${GREEN_COLOR}cd .."
        echo -e ""
        echo -e "${DEFAULT_COLOR}Once this is complete, run the deploy command again"
    else
        # Virtual environment does not exist
        echo -e "${DEFAULT_COLOR}The virtual environment does not exist."
        echo -e "${DEFAULT_COLOR}To create and activate the virtual environment, run the following commands:"
        echo -e ""
        echo -e "${GREEN_COLOR}cd cdk"
        echo -e "${GREEN_COLOR}python3 -m venv .venv"
        echo -e "${GREEN_COLOR}source .venv/bin/activate"
        echo -e "${GREEN_COLOR}python3 -m pip install -r requirements.txt"
        echo -e "${GREEN_COLOR}cd .."
        echo -e ""
        echo -e "${DEFAULT_COLOR}Once this is complete, run the deploy command again"
    fi
    exit 1
fi

user_pool_id=$(aws cognito-idp list-user-pools --max-results 60 --query 'UserPools[?contains(Name, `ChatbotUserPool`)].Id' --output text)
if [ -n "$user_pool_id" ] && [ "$user_pool_id" != "None" ]; then
    cognitoDomain=$(aws cognito-idp describe-user-pool --user-pool-id "$user_pool_id" --query 'UserPool.Domain' --output text)
    if [ -n "$cognitoDomain" ] && [ "$cognitoDomain" != "None" ]; then
        echo -e "${DEFAULT_COLOR}User pool found with ID $user_pool_id and domain $cognitoDomain"
    else
        echo -e "${DEFAULT_COLOR}User pool found with ID $user_pool_id, but no Domain"
        cognitoDomain="genchatbot-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)-$(date +%y%m%d%H%M)"
        echo -e "${DEFAULT_COLOR}New Domain Set: $cognitoDomain"
    fi
else
    cognitoDomain="genchatbot-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 8)-$(date +%y%m%d%H%M)"
    echo -e "${DEFAULT_COLOR}No User Pool or Domain Found, Creating New Domain: $cognitoDomain"
fi

get_certificate_arn() {
    local cname="$1"
    local wildcard_cname="*.$cname"

    # Check for a direct match first
    certificate_arn=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='$cname'].CertificateArn|[0]" --output text)

    # If no direct match, check for a wildcard certificate
    if [ -z "$certificate_arn" ]; then
        certificate_arn=$(aws acm list-certificates --query "CertificateSummaryList[?DomainName=='$wildcard_cname'].CertificateArn|[0]" --output text)
    fi

    echo "$certificate_arn"
}


# Check if cname exists, else prompt user
cname=""
certificate_arn=""
# if [ -f cname.ref ]; then
#   cname=$(cat cname.ref)
# else
#   read -p "Would you like to add a DNS CNAME Record for this website such as ai.example.com? You will still need to update your DNS manually after the deployment is complete (y/n) " add_cname
#   case "$add_cname" in
#     [yY][eE][sS]|[yY])
#       while true; do
#         read -p "Enter the CNAME here (e.g., api.example.com): " cname
#         if [[ "$cname" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]+$ ]]; then
#           echo "$cname" > cname.ref
#           certificate_arn=$(get_certificate_arn "$cname")
#           if [ -n "$certificate_arn" ]; then
#             echo "Found certificate ARN: $certificate_arn"
#             break
#           else
#             echo "No certificate found for $cname or *.$cname One will be created"
#             certificate_arn=""
#           fi
#         else
#           echo "Error: Invalid CNAME format. Please try again."
#         fi
#       done
#       ;;
#     *)
#       echo "" > cname.ref
#       ;;
#   esac
# fi

# Check if allowlistDomain exists, else prompt user
allowListDomain=""
if [ -f allowlistdomain.ref ]; then
  allowListDomain=$(cat allowlistdomain.ref)
else
  read -p "Would you like to add one or more email domains to an allowlist for user registration? (y/n) " add_allowlist
  case "$add_allowlist" in
    [yY][eE][sS]|[yY])
      while true; do
        read -p "Enter the allowlist domains separated by commas (Example: @amazon.com,@example.ca): " allowListDomain
        valid=true
        IFS=',' read -ra domains <<< "$allowListDomain"
        for domain in "${domains[@]}"; do
          if ! [[ "$domain" =~ ^@?[a-zA-Z0-9.-]+$ ]]; then
            valid=false
            break
          fi
        done
        if $valid; then
          echo "$allowListDomain" > allowlistdomain.ref
          break
        else
          echo "Error: Invalid domain format. Please try again."
        fi
      done
      ;;
    *)
      echo "" > allowlistdomain.ref
      ;;
  esac
fi

./recreate-python-lambda-layer.sh
#change to cdk Directory
cd cdk
if [ ! -d "./static-website-source" ]; then
    # Create the directory if it doesn't exist
    echo "Creating static-website-source directory..."
    mkdir ./static-website-source
    touch ./static-website-source/placeholder.txt
fi

# Install Python dependencies
python3 -m pip install -r requirements.txt

# Check if CDK bootstrap has been completed
bootstrap_ref_file="bootstrap.ref"

if [ -f "$bootstrap_ref_file" ]; then
    echo "Skipping CDK bootstrap process."
else
    read -p "Do you want to run cdk Bootstrap now (if you don't know, assume Yes)? (y/n) " run_bootstrap
    case "$run_bootstrap" in
        [yY][eE][sS]|[yY])
            echo "Running CDK bootstrap..."
            if [ -n "$cname" ] && [ "$cname" != "None" ] && [ "$cname" != "null" ]; then
                cdk bootstrap --require-approval never --context cname="$cname" --context certificate_arn="$certificate_arn" --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain"
            else
                cdk bootstrap --require-approval never --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain"
            fi
            
            if [ $? -eq 0 ]; then
                echo "CDK bootstrap completed successfully."
            else
                echo "Failed to run CDK bootstrap."
                exit 1
            fi
            ;;
        *)
            echo "Skipping CDK bootstrap process."
            ;;
    esac
fi
touch "$bootstrap_ref_file"

# Deploy the CDK app
if [ -n "$cname" ] && [ "$cname" != "None" ] && [ "$cname" != "null" ]; then
    cdk deploy --outputs-file outputs.json --context cname="$cname" --context certificate_arn="$certificate_arn" --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain" --require-approval never $app_flag $context_flag $debug_flag $profile_flag $tags_flag $force_flag $verbose_flag $role_arn_flag
else
    cdk deploy --outputs-file outputs.json --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain" --require-approval never $app_flag $context_flag $debug_flag $profile_flag $tags_flag $force_flag $verbose_flag $role_arn_flag
fi
if [ $? -ne 0 ]; then
    echo "Error: CDK deployment failed. Exiting script."
    exit 1
fi

#### START BUILDING REACT APP ####
# Check if outputs.json exists
if [ ! -f "./outputs.json" ]; then
    echo "Error: outputs.json file not found in the current directory."
    exit 1
fi

# Extract values from outputs.json
websocketapiendpoint=$(jq -r '.ChatbotWebsiteStack.websocketapiendpoint' ./outputs.json)
region=$(jq -r '.ChatbotWebsiteStack.region' ./outputs.json)
userpoolid=$(jq -r '.ChatbotWebsiteStack.userpoolid' ./outputs.json)
userpoolclientid=$(jq -r '.ChatbotWebsiteStack.userpoolclientid' ./outputs.json)
awschatboturl=$(jq -r '.ChatbotWebsiteStack.AWSChatBotURL' ./outputs.json)

# Generate ./react-chatbot/src/variables.js
mkdir -p ./react-chatbot/src/

variables_file="./react-chatbot/src/variables.js"
new_variables_content=$(cat <<HEREDOC_DELIMITER
const websocketUrl = '$websocketapiendpoint';

export { websocketUrl };
HEREDOC_DELIMITER
)


if [ -f "$variables_file" ]; then
    # File exists, compare contents
    existing_variables_content=$(cat "$variables_file")
    if [ "$existing_variables_content" != "$new_variables_content" ]; then
        # Contents are different, update the file
        printf "%s" "$new_variables_content" > "$variables_file"
        echo "variables.js file updated."
    else
        echo "variables.js file is up-to-date."
    fi
else
    # File doesn't exist, create it
    printf "%s" "$new_variables_content" > "$variables_file"
    echo "variables.js file created."
fi

# Generate ./react-chatbot/src/config.json
config_file="./react-chatbot/src/config.json"
new_config_content=$(cat <<HEREDOC_DELIMITER
{
  "aws_project_region": "${region}",
  "aws_cognito_region": "${region}",
  "aws_user_pools_id": "${userpoolid}",
  "aws_user_pools_web_client_id": "${userpoolclientid}"
}
HEREDOC_DELIMITER
)

if [ -f "$config_file" ]; then
    # File exists, compare contents
    existing_config_content=$(cat "$config_file")
    if [ "$existing_config_content" != "$new_config_content" ]; then
        # Contents are different, update the file
        printf "%s" "$new_config_content" > "$config_file"
        echo "config.json file updated."
    else
        echo "config.json file is up-to-date."
    fi
else
    # File doesn't exist, create it
    printf "%s" "$new_config_content" > "$config_file"
    echo "config.json file created."
fi

echo "Config files processed successfully!"

# Change to the cdk/react-chatbot directory
cd ./react-chatbot

# Install dependencies and build the React application
npm install
if [ $? -ne 0 ]; then
    echo -e "${RED_COLOR}Error: npm install failed. Exiting script.${DEFAULT_COLOR}"
    exit 1
fi
npm run build
if [ $? -ne 0 ]; then
    echo -e "${RED_COLOR}Error: npm run build failed. Exiting script.${DEFAULT_COLOR}"
    exit 1
fi

# Go back to the parent directory
cd ..
if [ -n "$cname" ] && [ "$cname" != "None" ] && [ "$cname" != "null" ]; then
    cdk deploy --outputs-file outputs.json --context cname="$cname" --context certificate_arn="$certificate_arn" --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain" --require-approval never $app_flag $context_flag $debug_flag $profile_flag $tags_flag $force_flag $verbose_flag $role_arn_flag
else
    cdk deploy --outputs-file outputs.json --context cognitoDomain="$cognitoDomain" --context allowlistDomain="$allowListDomain" --require-approval never $app_flag $context_flag $debug_flag $profile_flag $tags_flag $force_flag $verbose_flag $role_arn_flag
fi
if [ $? -ne 0 ]; then
    echo -e "${RED_COLOR}Error: CDK deployment failed. Exiting script.${DEFAULT_COLOR}"
    exit 1
fi
rm outputs.json

cd ..
echo -e "${GREEN_COLOR}Deployment complete!${DEFAULT_COLOR}"
# tell user to visit the url: awschatboturl
echo -e "${GREEN_COLOR}Visit the chatbot here: ${awschatboturl}${DEFAULT_COLOR}"
#if cname is not null and not empty, then print cname
if [ -n "$cname" ] && [ "$cname" != "None" ] && [ "$cname" != "null" ]; then
    echo -e "${GREEN_COLOR}Or you can use your DNS Entry: ${cname}${DEFAULT_COLOR}"
    echo -e "${DEFAULT_COLOR}The DNS entry will only work if you have configured your DNS correctly${DEFAULT_COLOR}"
fi
