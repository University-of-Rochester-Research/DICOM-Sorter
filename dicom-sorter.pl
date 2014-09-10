#!/usr/bin/perl

# ===[ dicom-sorter ]==========================================================
#
# Author:         Craig Harman (charman@rcbi.rochester.edu)
# Modified:       Evi Vanoost (vanooste@rcbi.rochester.edu)
# Created:        4 August 2004
# Last modified:  26 June 2014
# 
#   Usage, abbreviated:
#
#     dicom-sorter path_to_study_files
#
#
#   Description:
#
#     In brief, this script renames a DICOM file using information
#     extracted from the file's DICOM header.
#
#     [Requirements]
#
#       This script is designed to be used in conjunction with two
#       programs from the DCMTK DICOM toolkit. The script was tested
#       with DCMTK version 3.5.3, 3.6.0 and 3.6.1. The program should be 
#       thoroughly tested before being deployed in a production setting 
#       with a different version of DCMTK. DCMTK can be downloaded from:
#
#         http://dicom.offis.de/dcmtk.php.en
#
#       This script has been modified for Siemens and GE systems. 
#		This script will likely need to be modified if used with files from 
#		a different system.
#
#     [Usage]
#
#       This program is designed to be called by the DCMTK program
#       'storescp'.  storescp is a DICOM listener implementation
#       that listens on a user-specified port for DICOM file transfer
#       connections, and saves the DICOM files to a directory.  This
#       script should be called by using the '-xcs' option (aka the
#       '--exec-on-eostudy' option), which causes a script to be run
#       once a whole study has been received.  The '-xcs' option
#       must be used with the '-ss' ('--sort-conc-studies') option,
#       which places all of the files for a specific study in a
#       directory with a user-specified prefix.
#
#       So, for example, one way to call this program using storescp 
#       would be to start storescp with the following arguments:
#
#         storescp [other_args] -xcs "dicom-sorter #p" -ss study
#
#       The '#p' option causes storescp to pass the full path of
#       directory name to the dicom-sorter script.  
#
#       storescp will create a new directory for each study, and 
#       place all of the DICOM files for that study in that directory.
#       See the (poorly translated from German) storescp man page for 
#       more details.
#
#       This script depends on the DCMTK 'dcmdump' utility for 
#       extracting the headers from the DICOM files.
#
#     [How it works]
#
#       The script looks in the directory passed to it as a command
#       line argument.  It treats each file in this directory as a 
#       DICOM file, and tries to parse each files DICOM headers.  It
#       will attempt to move each file into a new directory based on
#       the information found in the DICOM headers.
#
#
# ========================================================================
# Modifications:
# January 2010: Headers with weird characters (such as ampersand)
# March 2011: Lock functionality seemed to be not working. Added LOCK_EX
# August 2011: Added duplicate detection
# August 2011: Added TE as part of the filename
# June 2014: Added GE scanner support
#
# ========================================================================

use Fcntl qw(:DEFAULT :flock);                          # flock(), sysopen()
use Digest::MD5;
use strict;
use Cwd 'abs_path';
use constant false => 0;
use constant true  => 1;
use File::Basename;
use File::Copy;

# Declare rename_dicomfile
sub rename_dicomfile($);

if (scalar(@ARGV) != 1) {
    print "ERROR: Usage is dicom-sorter.pl path_to_study_files\n\n";
    exit;
}
my $study_directory = shift;

# ===  Try to obtain lock  ===
my $lockfile = "/tmp/dicomd.lock";
print "Locking '$lockfile'\n";
open(LOCKFILE, '>'.$lockfile) or die "Can't open lock: $!";
print  "Trying to lock '$lockfile'...\n";
until (flock(LOCKFILE, LOCK_EX | LOCK_NB)) {
	print "Couldn't lock - waiting 10s.\n";
	sleep 10;
	unless (defined(fileno *LOCKFILE)) {
		print "Lock handle no longer valid.\n";
		open(LOCKFILE, $lockfile) or die "Can't open lock: $!";
	}
}
print "Locked on.\n";

# ===  Miscellaneous initialization  ===
# Set path to DCMTK utility dcmdump
our $DCMDUMP = "/usr/local/bin/dcmdump";

# Test to see if dcmdump is really executable
if (not -x $DCMDUMP) {
	print "$DCMDUMP not executable";
    exit;
}

open PERMFILE, dirname(abs_path($0)).'/permission-mapping.txt' or die "Can't open permissions file: $!\n";
my @perm_raw = <PERMFILE>;
our %permissions;
foreach (@perm_raw) {
	my @this_perm = split (/\s/, $_);
	$permissions{$this_perm[0]} = \@this_perm;
}

# ===  Read in and rename files  ===
# Attempt to get a list of all files in the directory
if (not opendir(STUDYDIR, $study_directory)) {
	print "Could not open $study_directory";
    exit;
}
my @allfiles = readdir STUDYDIR;
closedir STUDYDIR;

foreach (@allfiles) {
    # Ignore the filenames "." and ".."
    if (not $_ =~ /\.$/) {
		rename_dicomfile("$study_directory/$_");
    }
}

# Remove directory, which should now be empty
rmdir $study_directory;
exit;

sub md5sum ($) {
  my $file = shift;
  my $digest = "";
  eval{
    open(FILE, $file) or die "Can't find file $file\n";
    my $ctx = Digest::MD5->new;
    $ctx->addfile(*FILE);
    $digest = $ctx->hexdigest;
    close(FILE);
  };
  if($@){
    print $@;
    return "";
  }
  return $digest;
}

sub make_directory ($$$) {
    my @fullpath = split('\/', shift);
    my $owner = shift;
    my $group = shift;

    

	my $dname;
	foreach (@fullpath) {
		$dname = $dname . "/". $_; 
		# Create subdirectory, if it does not already exist
    	if (not -e "$dname") {
			if (not mkdir("$dname", 0770)) {
	    		return false;
			} else {
				my $uid = (getpwnam $owner)[2];
    			my $gid = (getgrnam $group)[2];
    
    			if ($uid == 0) {
    				print ("Error resolving username");
    				$owner = 'admin';
    				$group = 'admin';
   				}
				chown ($uid, $gid, "$dname");
    			chmod (0770, "$dname");
			}
    	}			
	}
    return true;
}

sub rename_dicomfile($) {
	my $line = shift;
    my $old_filename = $line;

    # ===  Extract DICOM fields using dcmdump program  ===
    #
    my @lines = `$DCMDUMP "$old_filename"`;

    # Test to see if there were any errors running dcmdump.
    if ($? != 0) {
	 print "Error: $?";
	 exit;
    }

    # The dcmdump utility prints out DICOM headers using the following format:
    #
    #   (0010,0010) PN [craig]                                  #   6, 1 PatientsName
    #   (0018,1030) LO [t1_se_tra_concat_2]                     #  18, 1 ProtocolName
    #   (0008,0021) DA [20040730]                               #   8, 1 SeriesDate
    #   (0008,0031) TM [105719.125000]                          #  14, 1 SeriesTime
    # 
    #                   ^^^^^^^^^^^^^                                    ^^^^^^^^^^
    #                   Field value                                      Field name
    #
    # The following loop extracts all the DICOM field names and values from dcmdump's
    # output, and puts them in a hash that is keyed by field name.
    # 
    my %headers;
    foreach my $line (@lines) {
		if ($line =~ /\[(.*)\]\s+#\s+\d+\,\s+\d+\s+(\w+)/) {
	    	$headers{$2} = $1;
		}
    }

    # If a first name and last name are provided, then the 'PatientsName' DICOM
    # is formatted as 'Lastname^Firstname' on Siemens systems.
    #
    my $patients_name = $headers{"PatientName"};
    $patients_name =~ s/(\s|&|<|>|\'|\^|\/|\\|\"|\,)+/\_/g;    # Replace special characters and spaces by _

    # The timestamp of the DICOM field SeriesTime has the format "HHMMSS.MMMMMNN"
    # We are only interested in a second-granularity timestamp, so we strip off everything
    # after and including the period.
    #
    my $series_time_1s_granularity = $headers{"SeriesTime"};
	if ($series_time_1s_granularity =~ /(\d+)(\.\d)*/) {
		$series_time_1s_granularity = $1;		
	}
	
    # Remove special characters from the 'SeriesDescription' field
    my $series_description = $headers{"SeriesDescription"};
    $series_description =~ s/(&|<|>|\'|\^|\/|\\|\"|\,)//g;      # Remove '&', '<', '>', "'", '^', '/', '\', '"' and ','
    $series_description =~ s/\s+/\_/g;        # Replace multi-whitespaces with 1 underscore
    # TODO: Are there any other characters I need to worry about?

    my $series_title = $headers{"SeriesNumber"} . "." . $series_description;

    # We modify the instanceNumber so that it is a string containing a four digit, right-justified
    # number with leading zeros.  This should force the filenames to be sorted by acquisition
    # time when they are sorted in alphabetical order.  If this is not done, we end up with files
    # listed in the following order:
    #
    #   image.1.dcm
    #   image.10.dcm
    #   image.11.dcm
    #   image.2.dcm
    #   image.3.dcm
    #   [...]
    #
    # when we want:
    #
    #   image.0001.dcm
    #   image.0002.dcm
    #   image.0003.dcm 
    #   [...]
    #   image.0010.dcm
    #   image.0011.dcm
    # 
    my $instanceNumber_4digits = sprintf "%.4d", $headers{"InstanceNumber"};
    my $series_date   = $headers{"SeriesDate"};
    my $echonumbers = $headers{"EchoNumbers"};

    my $new_filename = $patients_name . "." . $series_date . "." . $series_time_1s_granularity . "." . $series_title . "." . "Echo_" . $echonumbers . "." . $instanceNumber_4digits;
	$new_filename =~ s/(&|<|>|\'|\^|\/|\\|\")//g;

    # Add .DCM extension later

    # The DICOM header field 'StudyDescription' is created by concatenating the Syngo fields 
    # 'Region' and 'Exams' together, separated by the '^' character.  For example:
    #
    #   SeriesDescription = "ACHTMAN^FMRI"
    #
    # We split the field back into two separate fields.
    #
    my $studyDescription = $headers{"StudyDescription"};
    my $region;
    my $exams;
    
    if ($studyDescription =~ /(.+)\^(.+)/) {
		$region = $1;
		$exams = $2;
		#Strip special characters
   		$region =~ s/(&|<|>|\'|\^|\/|\\|\")//g;
		$exams =~ s/(&|<|>|\'|\^|\/|\\|\")//g;
    }
    
    # We have nothing left    
    if ($region eq "") {
        $region = $headers{"StudyDescription"};
    	$region =~ s/(&|<|>|\'|\^|\/|\\|\")//g;
   	}

    if ($exams eq "") {
        $exams = $headers{"StudyDescription"};
        $exams =~ s/(&|<|>|\'|\^|\/|\\|\")//g;
    }
    
    # Replace strings of whitespace with a single underscore, as some study
    # descriptions (like "HEAD CP^Brain") contain spaces.
    # TODO: Are there any other characters I need to worry about?
    $region =~ s/\s+/\_/g;
    $exams  =~ s/\s+/\_/g;
    
    # We initialize the full path here so that we can overwrite it if an
    # error occurs in the code below
    my $full_path = "$region/$exams/$patients_name/$series_date/$series_title";
	my $owner;
    my $group;
	
	if ($headers{"StationName"} =~ /UISPMR3T/) {
		# Sent from MedCenter 3T
		$full_path = "/zhongData/GE3T/".$full_path;
		$owner = "mtivarus";
		$group = "zhonggroup";
	} elsif ($headers{"InstitutionName"} =~ /UISP/ || $headers{"InstitutionName"} =~ /URMC/) {
		# Sent from MedCenter other
		my $stationname = $headers{"StationName"};
		$stationname =~ s/(&|<|>|\'|\^|\/|\\|\")//g;
		$full_path = "/zhongData/" . $stationname . "/".$full_path;
		$owner = "zhong";
		$group = "zhonggroup";
	} else {
		$full_path = $permissions{$region}[3]."/".$full_path;
		if (exists $permissions{$region}) {
			$owner = $permissions{$region}[1];
			$group = $permissions{$region}[2];
		} else {
			$owner = 'admin';
    		$group = 'admin';
    	}
	}

    # ===  Create directories to place file in  ===
    make_directory ($full_path, $owner, $group);	
    
    # === Check for duplicates ===
    # We need to store the original filename so we can add strings to it
    my $orig_new_filename = $new_filename;

    # If the file already exists
    if ( -e $full_path."/".$new_filename.".dcm") {
    	#print "Potential duplicate found\n";
        my $duplicate = 1;
       	# Calculate MD5 hash of existing filename. Do it only once. 
		my $md5_old = md5sum($old_filename);
        my $md5_new;
        # DEBUG: print ($md5_old);
        # As long as we have duplicates
        while ($duplicate) {
            # If the file already exists
            if ( -e $full_path."/".$new_filename.".dcm") {
                # Calculate the unique hash of the file
            	$md5_new = md5sum($full_path."/".$new_filename.".dcm");

            	# DEBUG: print $md5_new;
            	if ($md5_old eq $md5_new) {
                	# The files are identical so we can overwrite them
		   			# Exit the loop
            		$duplicate = 0;
           		} else {
                	# The files are not identical so we can't overwrite them. Add a NonDupeIndex
                	$new_filename = $orig_new_filename.'NonDupe'.$duplicate;
                	# DEBUG: print ($full_path."/".$new_filename);
                	# Increment the counter, do not exit the loop, do not collect 200
            		$duplicate++;
        		}
       		} else {
           		# Exit the loop
          		$duplicate = 0;
        	}
        }
   }


    # ===  Rename file and move it the appropriate directory  ===
    $new_filename = $new_filename . ".dcm";

    # Attempt to rename file
    if (!move ($old_filename, $full_path."/".$new_filename)) {
       	print "Error renaming: $old_filename to $full_path/$new_filename";
		exit;
    }

    #  Change permissions on file
    chmod(0660, $full_path."/".$new_filename);
    
    my $uid = (getpwnam $owner)[2];
    my $gid = (getgrnam $group)[2];
    
    if ($uid == 0) {
    	print ("Error resolving username");
    	$owner = 'admin';
    	$group = 'admin';
    }
    #  Change ownership of file
    chown($uid, $gid, $full_path."/".$new_filename);
}