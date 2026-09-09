// GENERATED from the web app's src/data — do not edit by hand.
//
// The same lists the website's registration wizard and directory filters use.
// They ship with the app rather than being fetched because a lawyer filling in
// the wizard on a train should not be blocked by a dropdown that needs the
// network — and because a state list that disagrees with the server's is how a
// profile ends up with a city and state that contradict each other.

/// A practice area. Matters within it come from the API, which knows the
/// current set; this is the stable top level.
class ServiceGroup {
  const ServiceGroup(this.name, this.slug);

  final String name;
  final String slug;
}

class RefData {
  const RefData._();

  /// Languages a lawyer may consult in.
  static const List<String> languages = [
    'Hindi',
    'English',
    'Marathi',
    'Bengali',
    'Telugu',
    'Tamil',
    'Gujarati',
    'Kannada',
    'Malayalam',
    'Punjabi',
    'Odia',
    'Urdu',
    'Assamese',
    'Konkani',
  ];

  /// Courts and tribunals a lawyer can practise in.
  static const List<String> courts = [
    'Supreme Court of India',
    'High Court',
    'District & Sessions Court',
    'Civil Court',
    'Family Court',
    'Consumer Forum',
    'Labour Court',
    'Magistrate Court (CJM/JMFC)',
    'Revenue Court',
    'National Company Law Tribunal (NCLT)',
    'Debt Recovery Tribunal (DRT)',
    'Income Tax Appellate Tribunal (ITAT)',
    'National Green Tribunal (NGT)',
    'Motor Accident Claims Tribunal (MACT)',
    'Lok Adalat',
  ];

  /// Every state and union territory, alphabetically. These strings must match
  /// the `state` on city records exactly.
  static const List<String> states = [
    'Andaman and Nicobar Islands',
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chandigarh',
    'Chhattisgarh',
    'Dadra and Nagar Haveli and Daman and Diu',
    'Delhi',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jammu and Kashmir',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Ladakh',
    'Lakshadweep',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Puducherry',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
  ];

  /// Cities per state, for the dependent city picker.
  static const Map<String, List<String>> statesCities = {
    'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Nellore', 'Kurnool', 'Rajahmundry', 'Kadapa', 'Tirupati', 'Kakinada', 'Anantapur', 'Vizianagaram', 'Eluru', 'Ongole', 'Chittoor', 'Machilipatnam', 'Srikakulam'],
    'Arunachal Pradesh': ['Itanagar', 'Naharlagun', 'Pasighat', 'Tawang', 'Ziro', 'Bomdila', 'Tezu', 'Along', 'Roing', 'Khonsa'],
    'Assam': ['Guwahati', 'Silchar', 'Dibrugarh', 'Jorhat', 'Nagaon', 'Tinsukia', 'Tezpur', 'Bongaigaon', 'Dhubri', 'Sivasagar', 'Goalpara', 'Barpeta', 'North Lakhimpur', 'Karimganj', 'Diphu'],
    'Bihar': ['Patna', 'Gaya', 'Bhagalpur', 'Muzaffarpur', 'Purnia', 'Darbhanga', 'Bihar Sharif', 'Arrah', 'Begusarai', 'Katihar', 'Munger', 'Chhapra', 'Saharsa', 'Sasaram', 'Hajipur', 'Dehri', 'Motihari', 'Bettiah', 'Siwan'],
    'Chhattisgarh': ['Raipur', 'Bhilai', 'Bilaspur', 'Korba', 'Durg', 'Rajnandgaon', 'Jagdalpur', 'Raigarh', 'Ambikapur', 'Dhamtari', 'Mahasamund', 'Kanker'],
    'Goa': ['Panaji', 'Margao', 'Vasco da Gama', 'Mapusa', 'Ponda', 'Bicholim', 'Curchorem', 'Cuncolim', 'Canacona'],
    'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Bhavnagar', 'Jamnagar', 'Junagadh', 'Gandhinagar', 'Anand', 'Nadiad', 'Morbi', 'Mehsana', 'Bharuch', 'Navsari', 'Vapi', 'Porbandar', 'Gandhidham', 'Valsad', 'Palanpur'],
    'Haryana': ['Gurgaon', 'Faridabad', 'Panipat', 'Ambala', 'Yamunanagar', 'Rohtak', 'Hisar', 'Karnal', 'Sonipat', 'Panchkula', 'Bhiwani', 'Sirsa', 'Bahadurgarh', 'Jind', 'Kaithal', 'Rewari', 'Palwal', 'Kurukshetra', 'Fatehabad'],
    'Himachal Pradesh': ['Shimla', 'Solan', 'Dharamshala', 'Mandi', 'Kullu', 'Hamirpur', 'Bilaspur', 'Una', 'Chamba', 'Nahan', 'Palampur', 'Baddi', 'Manali'],
    'Jharkhand': ['Ranchi', 'Jamshedpur', 'Dhanbad', 'Bokaro', 'Deoghar', 'Hazaribagh', 'Giridih', 'Ramgarh', 'Medininagar', 'Chaibasa', 'Dumka', 'Phusro'],
    'Karnataka': ['Bengaluru', 'Mysuru', 'Hubli-Dharwad', 'Mangaluru', 'Belagavi', 'Kalaburagi', 'Davanagere', 'Ballari', 'Vijayapura', 'Shivamogga', 'Tumakuru', 'Raichur', 'Bidar', 'Hospet', 'Hassan', 'Udupi', 'Chitradurga', 'Kolar', 'Mandya'],
    'Kerala': ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur', 'Kollam', 'Kannur', 'Alappuzha', 'Palakkad', 'Malappuram', 'Kottayam', 'Pathanamthitta', 'Idukki', 'Kasaragod', 'Wayanad', 'Ernakulam'],
    'Madhya Pradesh': ['Indore', 'Bhopal', 'Jabalpur', 'Gwalior', 'Ujjain', 'Sagar', 'Dewas', 'Satna', 'Ratlam', 'Rewa', 'Katni', 'Singrauli', 'Burhanpur', 'Khandwa', 'Morena', 'Bhind', 'Chhindwara', 'Vidisha', 'Shivpuri'],
    'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Nashik', 'Thane', 'Aurangabad', 'Solapur', 'Kolhapur', 'Amravati', 'Nanded', 'Sangli', 'Jalgaon', 'Akola', 'Latur', 'Dhule', 'Ahmednagar', 'Chandrapur', 'Parbhani', 'Navi Mumbai', 'Ichalkaranji'],
    'Manipur': ['Imphal', 'Thoubal', 'Bishnupur', 'Churachandpur', 'Kakching', 'Ukhrul', 'Senapati', 'Tamenglong'],
    'Meghalaya': ['Shillong', 'Tura', 'Jowai', 'Nongstoin', 'Williamnagar', 'Baghmara', 'Nongpoh'],
    'Mizoram': ['Aizawl', 'Lunglei', 'Champhai', 'Serchhip', 'Kolasib', 'Saiha', 'Mamit'],
    'Nagaland': ['Kohima', 'Dimapur', 'Mokokchung', 'Tuensang', 'Wokha', 'Zunheboto', 'Mon', 'Phek'],
    'Odisha': ['Bhubaneswar', 'Cuttack', 'Rourkela', 'Berhampur', 'Sambalpur', 'Puri', 'Balasore', 'Bhadrak', 'Baripada', 'Jharsuguda', 'Jeypore', 'Angul', 'Dhenkanal'],
    'Punjab': ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala', 'Bathinda', 'Mohali', 'Hoshiarpur', 'Pathankot', 'Moga', 'Batala', 'Barnala', 'Firozpur', 'Kapurthala', 'Phagwara', 'Sangrur', 'Khanna', 'Muktsar'],
    'Rajasthan': ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota', 'Ajmer', 'Bikaner', 'Alwar', 'Bharatpur', 'Sikar', 'Pali', 'Bhilwara', 'Sri Ganganagar', 'Tonk', 'Beawar', 'Hanumangarh', 'Churu', 'Jhunjhunu', 'Chittorgarh', 'Nagaur'],
    'Sikkim': ['Gangtok', 'Namchi', 'Gyalshing', 'Mangan', 'Rangpo', 'Singtam', 'Jorethang'],
    'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem', 'Tirunelveli', 'Tiruppur', 'Erode', 'Vellore', 'Thoothukudi', 'Dindigul', 'Thanjavur', 'Nagercoil', 'Karur', 'Kanchipuram', 'Cuddalore', 'Kumbakonam', 'Hosur', 'Sivakasi'],
    'Telangana': ['Hyderabad', 'Warangal', 'Nizamabad', 'Karimnagar', 'Khammam', 'Ramagundam', 'Mahbubnagar', 'Nalgonda', 'Adilabad', 'Secunderabad', 'Siddipet', 'Suryapet', 'Miryalaguda'],
    'Tripura': ['Agartala', 'Udaipur', 'Dharmanagar', 'Kailashahar', 'Belonia', 'Ambassa', 'Khowai', 'Teliamura'],
    'Uttar Pradesh': ['Lucknow', 'Kanpur', 'Ghaziabad', 'Agra', 'Varanasi', 'Meerut', 'Prayagraj', 'Bareilly', 'Aligarh', 'Moradabad', 'Saharanpur', 'Gorakhpur', 'Noida', 'Firozabad', 'Jhansi', 'Muzaffarnagar', 'Mathura', 'Ayodhya', 'Rampur', 'Shahjahanpur', 'Farrukhabad', 'Mau', 'Hapur', 'Etawah'],
    'Uttarakhand': ['Dehradun', 'Haridwar', 'Roorkee', 'Haldwani', 'Rudrapur', 'Kashipur', 'Rishikesh', 'Nainital', 'Mussoorie', 'Almora', 'Pithoragarh', 'Kotdwar'],
    'West Bengal': ['Kolkata', 'Howrah', 'Durgapur', 'Asansol', 'Siliguri', 'Bardhaman', 'Malda', 'Baharampur', 'Habra', 'Kharagpur', 'Haldia', 'Krishnanagar', 'Medinipur', 'Jalpaiguri', 'Darjeeling', 'Cooch Behar', 'Bankura'],
    'Andaman and Nicobar Islands': ['Port Blair', 'Diglipur', 'Rangat', 'Mayabunder', 'Car Nicobar'],
    'Chandigarh': ['Chandigarh'],
    'Dadra and Nagar Haveli and Daman and Diu': ['Silvassa', 'Daman', 'Diu'],
    'Delhi': ['New Delhi', 'Delhi', 'North Delhi', 'South Delhi', 'East Delhi', 'West Delhi', 'Dwarka', 'Rohini', 'Pitampura', 'Karol Bagh', 'Saket', 'Janakpuri'],
    'Jammu and Kashmir': ['Srinagar', 'Jammu', 'Anantnag', 'Baramulla', 'Udhampur', 'Kathua', 'Sopore', 'Kupwara', 'Pulwama'],
    'Ladakh': ['Leh', 'Kargil'],
    'Lakshadweep': ['Kavaratti', 'Agatti', 'Amini', 'Andrott'],
    'Puducherry': ['Puducherry', 'Karaikal', 'Yanam', 'Mahe'],
  };

  /// Practice areas.
  static const List<ServiceGroup> services = [
    ServiceGroup('Civil Law', 'civil-lawyer'),
    ServiceGroup('Criminal Law', 'criminal-lawyer'),
    ServiceGroup('Family Law', 'family-lawyer'),
    ServiceGroup('Property Law', 'property-lawyer'),
    ServiceGroup('Corporate Law', 'corporate-lawyer'),
    ServiceGroup('Tax Law', 'tax-lawyer'),
    ServiceGroup('Labour & Employment', 'labour-lawyer'),
    ServiceGroup('Constitutional Law', 'constitutional-lawyer'),
    ServiceGroup('Consumer Law', 'consumer-lawyer'),
    ServiceGroup('Intellectual Property', 'intellectual-property-lawyer'),
    ServiceGroup('Real Estate / RERA', 'real-estate-lawyer'),
    ServiceGroup('Immigration Law', 'immigration-lawyer'),
  ];

  static List<String> citiesIn(String state) =>
      statesCities[state] ?? const <String>[];

  static List<String> get serviceNames =>
      services.map((s) => s.name).toList(growable: false);
}
