DICOM-Sorter
============
In brief, this script renames a DICOM file using information extracted from the file's DICOM header.

[Requirements]
       This script is designed to be used in conjunction with two
       programs from the DCMTK DICOM toolkit. The script was tested
       with DCMTK version 3.5.3, 3.6.0 and 3.6.1. The program should be 
       thoroughly tested before being deployed in a production setting 
       with a different version of DCMTK. DCMTK can be downloaded from:

         http://dicom.offis.de/dcmtk.php.en

      This script has been modified for Siemens and GE systems. 
		  This script will likely need to be modified if used with files from 
		  a different system.

[Usage]

       This program is designed to be called by the DCMTK program
       'storescp'.  storescp is a DICOM listener implementation
       that listens on a user-specified port for DICOM file transfer
       connections, and saves the DICOM files to a directory.  This
       script should be called by using the '-xcs' option (aka the
       '--exec-on-eostudy' option), which causes a script to be run
       once a whole study has been received.  The '-xcs' option
       must be used with the '-ss' ('--sort-conc-studies') option,
       which places all of the files for a specific study in a
       directory with a user-specified prefix.

       So, for example, one way to call this program using storescp 
       would be to start storescp with the following arguments:

         storescp [other_args] -xcs "dicom-sorter #p" -ss study

       The '#p' option causes storescp to pass the full path of
       directory name to the dicom-sorter script.  

       storescp will create a new directory for each study, and 
       place all of the DICOM files for that study in that directory.
       See the (poorly translated from German) storescp man page for 
       more details.

       This script depends on the DCMTK 'dcmdump' utility for 
       extracting the headers from the DICOM files.

[How it works]

       The script looks in the directory passed to it as a command
       line argument.  It treats each file in this directory as a 
       DICOM file, and tries to parse each files DICOM headers.  It
       will attempt to move each file into a new directory based on
       the information found in the DICOM headers.
