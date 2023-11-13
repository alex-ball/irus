=pod

=head1 PIRUS 'PUSH' implementation

The official location for this EPrints extension is L<https://github.com/eprintsug/irus/>.

Please consult the README there for details about this implementation.

If there are any problems or bugs, please open an issue in that GitHub repository.

Released to the public domain (or CC0 depending on your juristiction).

USE OF THIS EXTENSION IS ENTIRELY AT YOUR OWN RISK

=head2 Installation / Implementation 

Please see the L<Installation|https://github.com/eprintsug/irus#installation> 
or L<Implementation|https://github.com/eprintsug/irus#implementation> sections
of the README.

=head2 Changes

For recent changes, please see L<https://github.com/eprintsug/irus#changes>  

1.05 Sebastien Francois <sf2@ecs.soton.ac.uk>

Conform to 2014 guidelines (see Event::PIRUS.pm)

1.02 Justin Bradley <jb4@ecs.soton.ac.uk>

Compatibility fixes for 3.2.

1.01 Tim Brody <tdb2@ecs.soton.ac.uk>

Fixed reference to 'jtitle' instead of 'publication'

1.00 Tim Brody <tdb2@ecs.soton.ac.uk>

Initial version

=cut

require LWP::UserAgent;
require LWP::Protocol::https;
require LWP::ConnCache;

# modify the following URL to the PIRUS tracker location
$c->{pirus}->{tracker} = "https://irus.jisc.ac.uk/counter/";
# during testing (or on a test server), the following should be used:
#$c->{pirus}->{tracker} = "https://irus.jisc.ac.uk/counter/test/";

# you may want to revise the settings for the user agent e.g. increase or
# decrease the network timeout
$c->{pirus}->{ua} = LWP::UserAgent->new(
	from => $c->{adminemail},
	agent => $c->{version},
	timeout => 20,
	conn_cache => LWP::ConnCache->new,
);

# If you need to go via a proxy to communicate with the tracker,
# add the following line to a local config file
#$c->{pirus}->{ua}->proxy('https', 'FULL-URL-TO-YOUR-PROXY-SERVER');

# This config value controls whether failed requests are logged into the
# Apache error log.
# By default some basic details are included in the description of the replay event.
# If you need additional debugging, copy the following line into a repository-specific
# config file, uncomment it, restart Apache and see what is in the logs.
# should get added 
# $c->{pirus}->{verbose_error_logging} = 1;

# Enable the Event plugin for replays
$c->{plugins}->{"Event::PIRUS"}->{params}->{disable} = 0;

##############################################################################

$c->add_dataset_trigger( 'access', EPrints::Const::EP_TRIGGER_CREATED, sub {
	my( %args ) = @_;

	my $repo = $args{repository};
	my $access = $args{dataobj};
	my $plugin = $repo->plugin( "Event::PIRUS" );

	my $request_url = $repo->current_url( host => 1 );

	my $r = $plugin->log( $access, $request_url );

	if( defined $r && !$r->is_success )
	{
		my $fail_message = "PIRUS dataset trigger failed to send data to tracker.\n " . $r->as_string;
		my $event = EPrints::DataObj::EventQueue->create_unique( $repo, {
			pluginid    => "Event::PIRUS",
			action      => "replay",
			params      => [ $access->id, $request_url ],
			description => $fail_message,
		});
		if( defined $event )
		{
			$event->commit;
		}

		if( $repo->config( "pirus", "verbose_error_logging" ) )
		{
			$fail_message .= "\nAccessID that failed: " . $access->id;
			$fail_message .= "\nURL of request that failed: " . $r->request->uri;
			$repo->log( $fail_message );
		}
	}
});
