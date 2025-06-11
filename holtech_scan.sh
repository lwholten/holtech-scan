#!/bin/bash

# --- Helper Functions ---
verbose_echo() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "["$(date +"%H:%M:%S")"]: $*" # Print all arguments passed to verbose_echo
    fi
}
tstamp_echo() {
    echo "["$(date +"%H:%M:%S")"]: $*"
}

# --- Global Variables ---
VERBOSE=0 # Verbose output is 0 by default
TEST=0 # Test mode is 0 by default
AUTO_FILE_NAMES=0 # Auto generated file names are 0 by default
TARGET_DIRECTORY="/home/$USER/Documents/Scans/" # Target storage location for saved scans#
OPEN_FILE=0 # Toggle to open file creation, 0 by default
PRINT_FILE=0 # Toggle to print file creation, 0 by default
HELPTEXT="""
    [ARGUMENTS]         [DESCRIPTION]                   [DEFAULT]
    -h --help:          Show help menu                  False
    -v --verbose:       Enable verbose output           False
    -t --test:          Enable test mode                False
    -a --auto:          Auto generate file names        False
    -d --directory:     Set directory for saved scans   (/home/$USER/Documents/Scans/)
    -o --open:          Open the file creation        False
    -p --print:         Print the file creation       False
"""
PRINTERTEXT="""
    It appears that no default printer is set on this system.
    Use the 'lpoptions' command to set one:
        1. List available printers using 'lpstat -p -d'
        2. Set a default printer using 'lpoptions -d <printer_name>'

    Try again once the issue is resolved.
"""

# --- Argument Handling --- 
# Function argument checks and responses
while [[ "$#" -gt 0 ]]; do # Loop while there are arguments left
    case "$1" in # Check the first argument
        -h|--help)
            tstamp_echo "${HELPTEXT}"
            exit 1
            ;;
        -v|--verbose)
            VERBOSE=1 # Set verbose output to 1
            verbose_echo "Verbose mode (-v) enabled."
            shift # Consume the -v argument
            ;;
        -t|--test)
            TEST=1 # Set test mode to 1
            verbose_echo "Test mode (-t) enabled."
            shift # Consume the -t argument
            ;;
        -a|--auto)
            AUTO_FILE_NAMES=1 # Set test mode to 1
            verbose_echo "Automatic mode (-a) enabled."
            shift # Consume the -a argument
            ;;
        -d|--directory)
            shift # Consume the -d argument
            # Check argument is not another flag
            if [[ -n "$1" && "$1" != -* ]]; then
                TARGET_DIRECTORY="$1"
                verbose_echo "Target directory set to '$TARGET_DIRECTORY'."
                shift # Consume the directory path argument
            else
                tstamp_echo "Error: --directory requires a directory path." >&2
                exit 1
            fi
            ;;
        -o|--open)
            OPEN_FILE=1 # Set open file mode to 1
            verbose_echo "Open file (-o) enabled."
            shift # Consume the -o argument
            ;;
        -p|--print)
            PRINT_FILE=1 # Set print file mode to 1
            verbose_echo "Print file (-p) enabled."
            shift # Consume the -p argument
            ;;
                        
        *)
            tstamp_echo "Error: Unknown argument: $1" >&2 # Report the unknown argument
            exit 1 # Throw error if an unknown argument is provided
            ;;
    esac
done

# --- Input Sanitation ---
fetch_fileext() {
    local filename="$1"
    local extension="${filename##*.}"

    if [[ "$filename" == "$extension" ]]; then
        extension="" # None found
        return 1 # Fail
    elif [[ "$filename" == ".*" && "$filename" != *.* ]]; then # Multiple dot support
        extension=""
        return 1 # Fail
    fi
    echo $extension # Output file extension
    return 0 # Success
}

validate_filename() {
    local proposed_name="$1" # Save user input as proposed name
    local invalid_chars='/\x00' # Store invalid characters (null byte etc.)
    local valid_filetypes=[]

    # Empty input
    if [[ -z "$proposed_name" ]]; then
        tstamp_echo "Error: Filename cannot be empty." >&2
        return 1
    fi

    # Forbidden characters
    if [ -n "$invalid_chars" ] && echo "$proposed_name" | grep -q "[${invalid_chars}]"; then
        tstamp_echo "Error: Filename contains forbidden characters." >&2
        return 1
    fi

    # Hyphens
    if [[ "$proposed_name" == -* ]]; then
        tstamp_echo "Error: Filename cannot start with a hyphen (-)." >&2
        return 1
    fi

    # Reserved names
    if [[ "$proposed_name" == "." || "$proposed_name" == ".." ]]; then
        tstamp_echo "Error: Filename cannot be '.' or '..'." >&2
        return 1
    fi

    # Leading spaces
    if [[ "$proposed_name" =~ ^[[:space:]]|[[[:space:]]]$ ]]; then
        tstamp_echo "Error: Filename cannot start or end with spaces." >&2
        return 1
    fi

    # Fetch file extension
    FILE_EXTENSION=$(fetch_fileext "$proposed_name")
    verbose_echo "Found extension '$FILE_EXTENSION' for '$proposed_name'"

    # File extension checks
    if [[ $FILE_EXTENSION = "" ]]; then
        tstamp_echo "Error: Filename must have an extension"
        return 1
    elif [[ $FILE_EXTENSION != "pdf" ]]; then
        tstamp_echo "Error: File extension is not supported"
        return 1
    fi

    # If all goes well, allocate the proposed name as the valifated file name
    VALIDATED_FILENAME="$proposed_name"
    verbose_echo "Filename '$VALIDATED_FILENAME' is valid."

    return 0 # Success
}

# --- Handlers ---
# File name handling
tstamp_echo "Checking filename..."
# Generate a filename if the -a argument was provided or ask for input
if [[ "$AUTO_FILE_NAMES" -eq 0 ]]; then 
    verbose_echo "Manual filename required."
    FILENAME="" # Initialise filename variable
    while true; do
        read -p "Please enter a filename for the scan (e.g. MyScan.pdf): " fname

        verbose_echo "Validating filename..."
        if validate_filename "$fname"; then
            FILENAME="$VALIDATED_FILENAME" # Store the entered name
            break # exit the loop because a valid input is taken
        fi
    done
else
    # Automatically generate file name using current timestamp
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    verbose_echo "Manual filename not required. Using timestamp: [$TIMESTAMP]."
    FILENAME="$TIMESTAMP.pdf"
    verbose_echo "Filename created: '$FILENAME'"
fi

# Check directory exists and create if not
tstamp_echo "Checking and creating directories..."

# Create the base target directory if it doesn't exist
mkdir -p "$TARGET_DIRECTORY"
verbose_echo "Ensured base directory '${TARGET_DIRECTORY}' exists."

# Construct and create the temporary files directory within TARGET_DIRECTORY
TEMP_PATH="${TARGET_DIRECTORY}temp/"
mkdir -p "$TEMP_PATH"
verbose_echo "TEMP path created and ensured directory '${TEMP_PATH}' exists."

# Construct and create the PDF output directory within TARGET_DIRECTORY
PDF_PATH="${TARGET_DIRECTORY}pdf/"
mkdir -p "$PDF_PATH"
verbose_echo "PDF path created and ensured directory '${PDF_PATH}' exists."

# Start scan procedure
if [[ "$TEST" -eq 0 ]]; then
    tstamp_echo "Performing scan..."
    # Tell the printer to perform a scan
    scanimage --format=tiff --mode Gray --resolution 300 > ${TEMP_PATH}"scan_result.tiff"
    STATUS=$?

    # Convert scan to PDF
    if [[ "$STATUS" -eq 0 ]]; then
        tstamp_echo "Scan Successful!"
    else
        tstamp_echo "Scan Unsuccessful."
        rm -f "${TEMP_PATH}scan_result.tiff" # Clean up any incomplete file
        exit 1 # CHANGE AT LATER DATE TO CONVERT ERROR INTO RESULT PDF
    fi
    verbose_echo "Converting to PDF..."
    convert ${TEMP_PATH}"scan_result.tiff" ${PDF_PATH}${FILENAME}
    PDF_CREATED=1
else
    verbose_echo "Test mode enabled. Faking scan..."
    # In test mode, create a dummy file and convert it to PDF
    DUMMY_TEXT_FILE="${TEMP_PATH}scan_result.txt"
    tstamp_echo "${HELPTEXT}" > "${DUMMY_TEXT_FILE}"
    verbose_echo "Converting dummy text file to PDF..."
    convert "TEXT:${DUMMY_TEXT_FILE}" "${PDF_PATH}${FILENAME}"
    PDF_CREATED=1
fi
# Remove temporary files
verbose_echo "Removing temp files..."
rm -r ${TEMP_PATH}

# --- Post-creation Actions ---
# Open the created PDF if the -o argument was provided and PDF was created
if [[ "$OPEN_FILE" -eq 1 && "$PDF_CREATED" -eq 1 ]]; then
    if [[ -f "${PDF_PATH}${FILENAME}" ]]; then # Check if PDF exists (it should!)
        verbose_echo "Opening generated PDF: ${PDF_PATH}${FILENAME}"
        xdg-open "${PDF_PATH}${FILENAME}" &>/dev/null & # Open file
    else
        tstamp_echo "Error: Cannot open file. PDF was not found at ${PDF_PATH}${FILENAME}" >&2
    fi
fi

# Print the created PDF if the -p argument was provided and PDF was created
if [[ "$PRINT_FILE" -eq 1 && "$PDF_CREATED" -eq 1 ]]; then
    if [[ -f "${PDF_PATH}${FILENAME}" ]]; then # Check if PDF exists (it should!)
        verbose_echo "Sending PDF to printer: ${PDF_PATH}${FILENAME}"
        # Capture stderr and exit status from lp command
        LP_OUTPUT=$(lp "${PDF_PATH}${FILENAME}" 2>&1)
        LP_STATUS=$?

        # Status code not succesful
        if [[ "$LP_STATUS" -ne 0 ]]; then
            tstamp_echo "Error: Failed to send PDF to printer. lp exit code: $LP_STATUS" >&2
            tstamp_echo "lp command output: $LP_OUTPUT" >&2

            # If the error is because of no default destination
            if echo "$LP_OUTPUT" | grep -q "No default destination"; then
                tstamp_echo "${PRINTERTEXT}";
            fi
        else
            verbose_echo "PDF successfully sent to printer."
        fi
    else
        tstamp_echo "Error: Cannot print file. PDF was not found at ${PDF_PATH}${FILENAME}" >&2
    fi
fi

tstamp_echo "Done."