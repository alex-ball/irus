package EPrints::Plugin::Event::PIRUS;

our $VERSION = v1.2.2;

@ISA = qw( EPrints::Plugin::Event );

use strict;

# @jesusbagpuss
# Counter v5 - send data about abstract page views (invesitgations) as well as downloads

# borrowed from EPrints 3.4's EPrints::OpenArchives::archive_id
sub _archive_id
{
	my( $repo, $any ) = @_;

	my $v1 = $repo->config( "oai", "archive_id" );
	my $v2 = $repo->config( "oai", "v2", "archive_id" );

	$v1 ||= $repo->config( "host" );
	$v1 ||= $repo->config("securehost");
	$v2 ||= $v1;

	return $any ? ($v1, $v2) : $v2;
}


sub replay
{
	my( $self, $accessid, $request_url ) = @_;

	my $repo = $self->{session};
	my $fail_message;

	my $access = EPrints::DataObj::Access->new( $repo, $accessid );
	unless ( defined $access )
	{
		$self->_log("PIRUS::replay: Access $accessid not found.");
		return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
	}

	my $r = $self->log( $access, $request_url );

	if( !defined $r || $r->is_success ) { return; }

	$fail_message = $r->as_string;

	$repo->log( "Attempt to re-send PIRUS trackback failed, trying again in 24 hours time" );
	$repo->log( "PIRUS replay event failed with the response:\n$fail_message" );

	# Reschedule the event:
	my $event = $self->{event};
	$start_time = time() + (24 * 60 * 60);   # try again in 24 hours time
	$event->set_value( "start_time",
		EPrints::Time::iso_datetime( $start_time )
	);
	$event->set_value( "description", $fail_message );

	# Set status to 'waiting' and commit:
	return EPrints::Const::HTTP_RESET_CONTENT;
}


# Returns undefined if Access cannot be turned into a ping.
sub log
{
	my( $self, $access, $request_url ) = @_;

	my $repo = $self->{session};

	my $url = URI->new(
		$repo->config( "pirus", "tracker" )
	);

	# We can only send a ping if we have enough information.
	# The specification for %qf_params can be found at
	# https://irus.jisc.ac.uk/r5/about/policies/tracker/

	# url_ver
	my %qf_params = ( url_ver => "Z39.88-2004", );

	# url_tim
	if ( $access->is_set("datestamp") )
	{
		my $url_tim = $access->value("datestamp");
		$url_tim =~ s/^(\S+) (\S+)$/$1T$2Z/;
		$qf_params{url_tim} = $url_tim;
	}
	else { return; }

	# rft_dat
	if ( $access->is_set("service_type_id") )
	{
		# This is either "?fulltext=yes" = file download (Request)
		# or "?abstract=yes" = landing page view (Investigation).
		$qf_params{rft_dat} =
		  $access->value("service_type_id") eq "?fulltext=yes"
		  ? "Request"
		  : "Investigation";
	}
	else { return; }

	# req_id
	if ( $access->is_set("requester_id") )
	{
		$qf_params{req_id} = $access->value("requester_id");
	}
	else { return; }

	# req_dat
	if ( $access->is_set("requester_user_agent") )
	{
		$qf_params{req_dat} = $access->value("requester_user_agent");
	}
	else { return; }

	# rft.artnum
	if ( $access->is_set("referent_id") )
	{
		my $artnum =
		  EPrints::OpenArchives::to_oai_identifier( _archive_id($repo),
			$access->value("referent_id"),
		  );
		$qf_params{'rft.artnum'} = $artnum;
	}
	else { return; }

	# svc_dat
	if ($request_url)
	{
		$qf_params{svc_dat} = $request_url;
	}
	else { return; }

	# rfr_dat
	$qf_params{rfr_dat} = $access->value("referring_entity_id") // q();

	# rfr_id
	$qf_params{rfr_id} =
		$repo->config("host")
	  ? $repo->config("host")
	  : $repo->config("securehost");

	$url->query_form(%qf_params);

	my $ua = $repo->config( "pirus", "ua" );

	return $ua->head( $url );
}

1;
