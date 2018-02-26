package Object;

use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '0.01';

sub set($$$) {
        my($self) = shift;
        my($what) = shift;
        my($value) = shift;

        $what =~ tr/a-z/A-Z/;

        $self->{ $what }=$value;
        return($value);
}

sub get($$) {
        my($self) = shift;
        my($what) = shift;

        $what =~ tr/a-z/A-Z/;
        my $value = $self->{ $what };

        return($self->{ $what });
}

sub new {
        my $proto  = shift;
        my $class  = ref($proto) || $proto;
        my $self   = {};

        bless($self,$class);

        my(%args) = @_;

        my($key,$value);
        while( ($key, $value) = each %args ) {
                $key =~ tr/a-z/A-Z/;
                $self->set($key,$value);
        }

        return($self);
}

package Toggl;

use strict;
use Carp;
use Data::Dumper;
use Storable qw(lock_store lock_retrieve);
use POSIX;

$Toggl::VERSION = '0.01';
@Toggl::ISA = qw(Object);

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};
        bless($self,$class);

	my(%defaults) = ( 
		weekformat => "%V", 
		yearformat => "%G", 
		togglhome => "$ENV{HOME}/.toggl"
	);
        my(%hash) = ( %defaults, @_) ;
        while ( my($key,$val) = each(%hash) ) {
                $self->set($key,$val);
        }
	$self->currweek($self->week());
	$self->curryear($self->year());
	if ( defined($ENV{TOGGLPROJ}) ) {
		$self->togglproj($ENV{TOGGLPROJ});
	}

	unless ( $self->togglhome() ) {
		croak "togglhome is not defined\n";
	}

	my($togglhome) = $self->togglhome();
	if ( ! -d $togglhome ) {
		chdir($togglhome);
		die "chdir($togglhome): $!\n";
	}

	my($curryeardir) = $self->togglhome() . "/" . $self->curryear();
	$self->curryeardir($curryeardir);
	if ( ! -d $curryeardir ) {
		mkdir($curryeardir);
		if ( ! -d $curryeardir ) {
			die "mkdir($curryeardir): $!\n";
		}
	}
	
	my($currtimefile) = $self->togglhome() . "/" . $self->curryear() . "/" . $self->week . ".tf";
	$self->currtimefile($currtimefile);
	
	unless ( $self->togglproj() ) {
		$self->togglproj($self->togglhome());
	}

        return($self);
}

sub debug {
	my($self) = shift;
	my($level) = shift;
	my($str) = shift;
	
	my($debug) = $self->get("debug");
	return  unless ( $debug );
	return  unless ( $debug >= $level );
	chomp($str);
	print "DEBUG($level): " . localtime(time) . " $str ***\n";
}

sub _accessor {
	my($self) = shift;
	my($key) = shift;
	my($value) = shift;
	if ( defined($value) ) {
		$self->debug(9,"Setting $key to $value");
		return ($self->set($key,$value));
	}
	else {
		return ($self->get($key));
	}
}
	

sub currweek { return ( shift->_accessor("_currweek",shift) ); }
sub curryear { return ( shift->_accessor("_curryear",shift) ); }
sub togglhome { return ( shift->_accessor("togglhome",shift) ); }
sub togglproj { return ( shift->_accessor("togglproj",shift) ); }
sub curryeardir { return ( shift->_accessor("_curryeardir",shift) ); }
sub currtimefile { return ( shift->_accessor("_currtimefile",shift) ); }

sub week {
	my($self) = shift;
	my($sec) = shift;
	$sec = time unless ( defined $sec );
	my($week) =  POSIX::strftime($self->get("weekformat"),localtime($sec));
	return ( sprintf("%02.2d",$week) );
}

sub year {
	my($self) = shift;
	my($sec) = shift;
	$sec = time unless ( defined $sec );
	return ( POSIX::strftime($self->get("yearformat"),localtime($sec)) );
}

sub createcurrdir {
	my($self) = shift;
}

sub readfile {
	my($self) = shift;
	my($file) = shift;
	my(@content) = ();

	if ( open(IN,"<$file") ) {
		$self->debug(5,"Reading $file");
		foreach ( <IN> ) {
			chomp;
			push(@content,$_);
		}
		close(IN);
	}
	return(@content);
}	

sub trim {
	my($self) = shift;
	my($str) = shift;
	return($str) unless ( defined($str) );
	$str =~	s/#.*//;
	$str =~	s/^\s*//;
	$str =~	s/\s*$//;
	return($str);
}
	
sub readprojfile {
	my($self) = shift;
	my($file) = shift;
	my(@content) = $self->readfile($file);

	my(%proj);
	my($id) = undef;
	my($comment) = undef;
	my($line) = 0;
	my(%allproj);
	foreach ( @content ) {
		$line++;
		$self->debug(5,"line $line in $file: $_");
		my($str) = $self->trim($_);

		my($key,$value) = split(/=/,$str);
		next unless ( $key );
		next unless ( $value );
		$self->debug(9,"key=[$key], value=[$value]");
		#
		# id=100
		# enable=yes
		# comment=som text
		#
		if ( $key =~ /id/i ) {
			$id=$value;
		}
		next unless ( $id );
		$allproj{$id}{$key}=$value;
	}
	# Clear all project with enable=n
	foreach $id ( sort keys %allproj ) {
		my($enable) = $allproj{$id}{enable};
		if ( $enable ) {
			next if ( $enable =~ /^n/i );
		}
		my($comment) = $allproj{$id}{comment};
		unless ( $comment ) {
			$comment = "project id $id";
		}
		$proj{$id}=$comment;
	}
	return(%proj);
}
	

sub readprojfiles {
	my($self) = shift;
	my($projdir);
	my($projects) = 0;
	my(%proj);
	foreach $projdir ( split(/:/,$self->togglproj() ) ) {
		$self->debug(5,"projdir=$projdir");
		my($projfile);
		foreach $projfile ( <$projdir/*.proj> ) {
			$self->debug(5,"projfile=$projfile");
			my(%projfile) = $self->readprojfile($projfile);
			foreach ( keys %projfile ) {
				$proj{$_}=$projfile{$_};
				$projects++;
			}
		}
	}
	unless ( $projects ) {
		die "No projects, exiting...\n";
	}
	return(%proj);
}

sub readtimefile {
	my($self) = shift;
	my($file) = shift;
	my(@content) = $self->readfile($file);
	my(%allinfo) = ();
	my($rec) = 0;
	foreach ( @content ) {
		my($str) = $self->trim($_);
		my($key,$value) = split(/=/,$str);
		next unless ( $key );
		next unless ( $value );
		if ( $key =~ /date/ ) {
			$rec++;
		}
		next unless ( $rec );
		$allinfo{$rec}{$key}=$value;
	}
	return(%allinfo);
}
		
sub readcurrtimefile {
	my($self) = shift;
	return( $self->readtimefile($self->currtimefile()) );
}

sub convtime2sec {
	my($self) = shift;
	my($time) = shift;
	my($hour,$min) = split(/:/,$time);
	my($sec) = $hour * 3600 + $min * 60;
	$self->debug(9,"Converted $time to hour=$hour, min=$min to sec=$sec");
	return($sec);
}

sub convtime2dursec {
	my($self) = shift;
	my($start) = shift;
	my($end) = shift;

	my($startsec) = $self->convtime2sec($start);
	my($endsec) = $self->convtime2sec($end);

	my($dursec) = $endsec - $startsec;
	$self->debug(9,"Duration $dursec sec");
	return($dursec);
}

sub startend2hour {
	my($self) = shift;
	my($start) = shift;
	my($end) = shift;

	my($dursec) = $self->convtime2dursec($start,$end);
	my($durhour) = int($dursec / 3600);
	my($durmin) = ($dursec - ( $durhour * 3600 )) / 60;
	my($durhourpart) = int(100 * $durmin / 60) / 100;
	my($res) = $durhour + $durhourpart;
	#print "start=$start end=$end dursec=$dursec durhour=$durhour durmin=$durmin ($durhourpart) res=[$res]\n";
	return($res);
}

sub convdursec2hour {
	my($self) = shift;
	my($dursec) = shift;

	my($durhour) = int($dursec / 3600);
	my($durmin) = ($dursec - ( $durhour * 3600 )) / 60;
	my($durhourpart) = int(100 * $durmin / 60) / 100;
	my($res) = $durhour + $durhourpart;
	#print "dursec=$dursec durhour=$durhour durmin=$durmin ($durhourpart) res=[$res]\n";
	return($res);
}

sub dates {
	my($self) = shift;
	my($hashp) = shift;
	
	my($first) = undef;
	my($last) = undef;

	my(%date);
	foreach ( sort keys %$hashp ) {
		my($date) = $hashp->{$_}{"date"};
		$date{$date}++;
	}
	return(sort keys %date);
}

sub weekreport {
	my($self) = shift;
	my($hashp) = shift;
	my(%times) = %$hashp;
	
	my(@dates) = $self->dates($hashp);
	my(%projnames) = $self->readprojfiles();


	my(%proj);
	while ( my($key,$value) = each(%times) ) {
		#print "Key=$key\n";
		#print Dumper(\$value);
		my($date) = $value->{"date"};
		my($start) = $value->{"start"};
		my($end) = $value->{"end"};
		my($proj) = $value->{"proj"};
		$self->debug(9,"proj=$proj, start=$start, end=$end");
		
		my($dursec) = $self->convtime2dursec($start,$end);
		#print "proj=$proj, date=$date, start=$start, end=$end, dursec=$dursec\n";
		$proj{$proj}{$date} += $dursec;
	}
	#print Dumper(\%proj);

	my($proj);
	my(%res);
	my($header);
	my($res);
	my(%projsum);
	my(%datesum);
	my($allsum) = 0;
	foreach $proj ( sort keys %proj ) {
		$header = sprintf("%-30.30s", "Project/Date");
		$res = sprintf("%-30.30s", $proj . " " . $projnames{$proj});

		my($date);
		foreach $date ( @dates ) {
			$header .= sprintf("%10.10s", $date);
			my($dursec) = $proj{$proj}{$date};
			$dursec = 0 unless ( $dursec );
			#next unless ( $dursec );
			$allsum += $dursec;
			$datesum{$date}+=$dursec;
			$projsum{$proj}+=$dursec;
			$dursec = 0 unless ( $dursec );
			my($hour) = $self->convdursec2hour($dursec);
			$res .= sprintf("%10.2f", $hour);
		}
		$header .= sprintf("%10.10s","Total");
		$res .= sprintf("%10.2f",$self->convdursec2hour($projsum{$proj}));
		$res{$proj} = $res;
	}
	my($tailer) = sprintf("%-30.30s","Totals");
	foreach ( @dates ) {
		$tailer .= sprintf("%10.2f",$self->convdursec2hour($datesum{$_}));
	}
	$tailer .= sprintf("%10.2f",$self->convdursec2hour($allsum));
		

	print $header . "\n";
	foreach ( sort keys %res ) {
		print $res{$_} . "\n";
	}
	print $tailer . "\n";
}
	
1;
