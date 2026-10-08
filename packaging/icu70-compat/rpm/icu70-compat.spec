# ICU 70 di SailfishOS 5.0, per il SOLO target di build 5.1 armv7hl.
# I pacchetti Qt6 armv7hl di piggz (qt6sb2, sailfish_latest_armv7hl) sono
# compilati su SFOS 5.0 e chiedono libicu*.so.70, mentre 5.1 ha ICU 73.
# Questo pacchetto NON va mai sul telefono: serve a installare Qt6 nel target;
# nell'app le .so.70 viaggiano dentro il bundle come il resto di Qt.
Name:       icu70-compat
Version:    70.1
Release:    1
Summary:    ICU 70 runtime libraries (from SailfishOS 5.0) for building against qt6sb2 armv7hl
License:    Unicode-DFS-2016
Source0:    LICENSE
ExclusiveArch: armv7hl

%description
%{summary}.

%prep

%build

%install
mkdir -p %{buildroot}%{_libdir} %{buildroot}%{_datadir}/licenses/%{name}
cp -a %{_sourcedir}/libicu*.so.70* %{buildroot}%{_libdir}/
cp -a %{_sourcedir}/LICENSE %{buildroot}%{_datadir}/licenses/%{name}/

%files
%{_libdir}/libicu*.so.70*
%{_datadir}/licenses/%{name}/LICENSE
