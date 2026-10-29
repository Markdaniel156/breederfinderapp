class LocationUtils {
  static String sanitizeAddress(String address) {
    // If the address contains 'Himamaylan', generalized to 'Himamaylan, Negros Occidental'
    // to hide specific locations like Barangays.
    if (address.contains('Himamaylan')) {
      return 'Himamaylan, Negros Occidental';
    }
    return address;
  }
}
