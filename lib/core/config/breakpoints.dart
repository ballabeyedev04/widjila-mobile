/// Seuil au-delà duquel l'application se dispose en « tablette ».
///
/// Une seule valeur pour toute l'application : elle était recopiée dans la
/// coquille et dans le tableau de bord, et deux écrans qui basculeraient à des
/// largeurs différentes donneraient une interface incohérente à la rotation.
///
/// 700 logical pixels : au-dessus de la plupart des téléphones en paysage,
/// en dessous de toutes les tablettes en portrait.
const double seuilTablette = 700;
