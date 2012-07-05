#------------------------------------------------------------------------------
# P A C K A G E  I N F O
#------------------------------------------------------------------------------

Summary: Collectd ConsoliDBIC plugin
Name: perl-Collectd-Plugins-ConsoliDBIC
Version: 0.1001
Release: 0
Group: Applications/System
Packager: Fabien Wernli
License: GPL+ or Artistic
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch: noarch
AutoReq: no
Source: http://search.cpan.org/CPAN/Collectd-Plugins-ConsoliDBIC-%{version}.tar.gz

Requires: perl(Collectd)
Requires: perl(Collectd::Unixsock)
Requires: perl(DBIx::Class)

%description
The ConsoliDBIC perl plugin consolidates values in collectd's cache
against data in a RDBMS using DBIx::Class.

%prep
%setup -q -n Collectd-Plugins-ConsoliDBIC-%{version}

#------------------------------------------------------------------------------
# B U I L D
#------------------------------------------------------------------------------

%build
PERL_MM_USE_DEFAULT=1 %{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

#------------------------------------------------------------------------------
# I N S T A L L 
#------------------------------------------------------------------------------

%install
rm -rf %{buildroot}

make pure_install PERL_INSTALL_ROOT=%{buildroot}
find %{buildroot} -type f -name .packlist -exec rm -f {} ';'
find %{buildroot} -depth -type d -exec rmdir {} 2>/dev/null ';'

### %check
### don't make test as plugin can't load without collectd

%clean
rm -rf %{buildroot}

#------------------------------------------------------------------------------
# F I L E S
#------------------------------------------------------------------------------

%files
%defattr(-,root,root,-)
%doc Changes README
%{perl_vendorlib}/*
%{_mandir}/man3/*.3*

%pre

%post

%preun

%postun

%changelog
# output by: date +"* \%a \%b \%d \%Y $USER"
* Fri Apr 20 2012 fwernli 0.1001-0
- release

