<?php
/*
 * 	Identity switch RoundCube Bundle
 *
 *	@copyright	(c) 2024 - 2025 Florian Daeumling, Germany. All right reserved
 * 	@license 	https://github.com/toteph42/identity_switch/blob/master/LICENSE
 */

$config['identity_switch.config'] = [ 		
	'gmail.com' => [
		'imap' => 'tls://imap.gmail.com:993',		
		'delimiter' => '.',
		'imap_user' => 'email',
		'smtp' => 'tls://smtp.gmail.com:587',
		'smtp_user' => 'email',
	],

	// Allow logging to 'logs/identity_switch.log'. Default is false.
	'logging'	=> true,

	// Allow new mail checking. Default is true.
	'check' 	=> true,

	// Specify interval for checking of new mails. Default is 5 min. (5 * 60 sec.)
	'interval' 	=> 300, 

	// Specify number of microseconds between each new mail check. Default is 0 micoseconds.
	// If value is greater than 1000000 (1 second) delay time is rounded to seconds.
	'delay' 	=> 0,

	// Specify no. of retries for reading data from mail server. Default is 10 times.
	'retries' 	=> 10, 
	
	// Max. number of seconds to wait for response from identity_switch_newmails.php
	// Defaults to 60 seconds
	'wait' 		=> 60,

	// Enable some debugging messages saved in log file. Default is false
	'debug' 	=> true,
];
