/* Copyright (c) 2014, Chris Berger, Jesse Freitas, Severin Ibarluzea,
Kiana McNellis, Kienan Knight-Boehm

All rights reserved.
This code is licensed using the BSD "3-Clause" license. Please refer to
"LICENSE.md" for the full license.
*/

#ifndef __HWTEMPLATE_H__
#define __HWTEMPLATE_H__

#include "TestCase.h"
//#include "GradingRubric.h"


const int hw_num = 0;
const std::string hw_name = "TestHW";

// Submission parameters
const int max_submissions = 20;
const int submission_penalty = 5;

// Compile-time parameters
const int max_clocktime = 2;		// in seconds
const int max_cputime = 2;			// in seconds
const int max_output_size = 100;	// in KB
	// OTHERS?

// Grading parameters
const int auto_pts = 30;
const int readme_pts = 2;
const int compile_pts = 3;
const int ta_pts = 20;

// File directories

// directory containing input files
const std::string input_files_dir = "";
// directory containing README and output files generated from student's code
const std::string student_files_dir = "../../testHWsubmit";
// directory containing expected output files
const std::string expected_output_dir = "";
// directory to store results from validation
const std::string results_dir = "";

// Test cases
const int num_testcases = 1;

TestCase case1(
  	"Case 1",
  	"./case1.exe",
    "./a.out 1> cout.txt 2> cerr.txt",
    "test_out.txt",
    "test_out.txt",
    "expected_test1.txt",
    5,
    false,
    NULL
);
  
  /* TODO: SHOULD COUT AND CERR CHECKS ALWAYS BE INCLUDED?
            IF SO, JUST DO THESE AUTOMATICALLY IN VALIDATOR*/
  
  /*Check cout_check;
  cout_check.setFilename("cout.txt");
  cout_check.setDescription("Standard OUTPUT (STDOUT)");
  cout_check.setExpected(NULL);
  //cout_check.setCompare();		// warn if not empty?
  cout_check.setSideBySide(true);
  cout_check.setPrintCheck(WARNING_OR_FAILURE);
  
  Check cerr_check;
  cerr_check.setFilename("cerr.txt");
  cerr_check.setDescription("Standard ERROR (STDERR)");
  cerr_check.setExpected(NULL);
  //cerr_check.setCompare();		// warn if not empty?
  cerr_check.setSideBySide(true);
  cerr_check.setPrintCheck(WARNING_OR_FAILURE);*/
  

#endif

