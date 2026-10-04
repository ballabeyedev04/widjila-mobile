source "https://rubygems.org"

# Déploiement Google Play (android/fastlane) et App Store (ios/fastlane) —
# voir docs/DEPLOIEMENT_ANDROID.md et docs/DEPLOIEMENT_IOS.md.
gem "fastlane", "~> 2.228"

# CocoaPods n'est utile qu'à la chaîne iOS, mais il doit être DANS ce paquet
# et non à côté.
#
# La machine macOS d'intégration livre bien un CocoaPods, seulement il est
# lié au Ruby du système. Or `ruby/setup-ruby` en installe un autre, et
# `pod` répond alors « CocoaPods is installed but broken » — après dix
# minutes de compilation, au moment où `flutter build ipa` en a besoin.
# Déclaré ici, il est résolu par le même Bundler que fastlane, et tout ce
# qui descend de `bundle exec` le trouve.
#
# `install_if` évite de l'installer sur les machines Linux de la chaîne
# Android, qui n'en ont que faire.
install_if -> { RUBY_PLATFORM.include?("darwin") } do
  gem "cocoapods", "~> 1.16"
end
