import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EmplacementPage extends StatefulWidget {
  const EmplacementPage({super.key});

  @override
  State<EmplacementPage> createState() => _EmplacementPageState();
}

  class _EmplacementPageState extends State<EmplacementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Column(   
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: _buildAddButtons(),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('sites').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Erreur: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("Aucun site trouvé."));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final siteDoc = snapshot.data!.docs[index];
                  return _buildSiteCard(siteDoc);
                },
              );
            },
          ),
        ),
      ],
    );
  }


  // Widget pour les boutons d'ajout
  Widget _buildAddButtons() {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('site'),
          icon: const Icon(Icons.add_location),
          label: const Text('Ajouter un Site'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('batiment'),
          icon: const Icon(Icons.apartment),
          label: const Text('Ajouter un Bâtiment'),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () => _showAddDialog('salle'),
          icon: const Icon(Icons.meeting_room),
          label: const Text('Ajouter une Salle'),
        ),
      ],
    );
  }

  // Widget pour afficher un site avec ses bâtiments
  Widget _buildSiteCard(DocumentSnapshot siteDoc) {
    final siteData = siteDoc.data() as Map<String, dynamic>;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(siteData['nom'] ?? 'Nom inconnu', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(siteData['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.location_city, color: Colors.blue),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('sites')
                .doc(siteDoc.id)
                .collection('batiments')
                .snapshots(),
            builder: (context, batimentsSnapshot) {
              if (batimentsSnapshot.hasError) {
                return Center(child: Text('Erreur: ${batimentsSnapshot.error}'));
              }
              
              if (batimentsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!batimentsSnapshot.hasData || batimentsSnapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucun bâtiment dans ce site."),
                );
              }
              
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: batimentsSnapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final batimentDoc = batimentsSnapshot.data!.docs[index];
                  return _buildBatimentCard(siteDoc, batimentDoc);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // Widget pour afficher un bâtiment avec ses salles
  Widget _buildBatimentCard(DocumentSnapshot siteDoc, DocumentSnapshot batimentDoc) {
    final batimentData = batimentDoc.data() as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.only(left: 32.0),
      child: ExpansionTile(
        title: Text(batimentData['nom'] ?? 'Nom inconnu', style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(batimentData['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.apartment, color: Colors.green),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('sites')
                .doc(siteDoc.id)
                .collection('batiments')
                .doc(batimentDoc.id)
                .collection('salle')
                //
                .snapshots(),
            builder: (context, sallesSnapshot) {
              if (sallesSnapshot.hasError) {
                return Center(child: Text('Erreur: ${sallesSnapshot.error}'));
              }
              
              if (sallesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!sallesSnapshot.hasData || sallesSnapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Aucune salle dans ce bâtiment."),
                );
              }
              
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sallesSnapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  final salleDoc = sallesSnapshot.data!.docs[index];
                  return _buildSalleItem(salleDoc);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // Widget pour afficher une salle
  Widget _buildSalleItem(DocumentSnapshot salleDoc) {
    final salleData = salleDoc.data() as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.only(left: 64.0),
      child: ListTile(
        title: Text(salleData['nom'] ?? 'Nom inconnu'),
        subtitle: Text(salleData['adresse'] ?? 'Adresse inconnue'),
        leading: const Icon(Icons.meeting_room, color: Colors.orange),
      ),
    );
  }

  // Fonction pour afficher la boîte de dialogue d'ajout
  /*void _showAddDialog(String type) {
    final TextEditingController nomController = TextEditingController();
    final TextEditingController adresseController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {

            /*DocumentSnapshot? selectedSite;
            DocumentSnapshot? selectedBatiment;*/
            String? selectedSiteId;
            String? selectedBatimentId;
            DocumentSnapshot? selectedSiteDoc;
            DocumentSnapshot? selectedBatimentDoc;
            

            return AlertDialog(
              title: Text('Ajouter un $type'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomController,
                      decoration: InputDecoration(labelText: 'Nom du $type'),
                    ),
                    TextField(
                      controller: adresseController,
                      decoration: InputDecoration(labelText: 'Adresse du $type'),
                    ),
                    if (type == 'batiment' || type == 'salle')
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('sites').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const CircularProgressIndicator();
                          final sites = snapshot.data!.docs;
                          return DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Site Parent'),
                            items: sites.map((site) {
                              return DropdownMenuItem<String>(
                                value: site.id,
                                child: Text(site['nom']),
                              );
                            }).toList(),
                            onChanged: (String? siteId) {
                              setState(() {
                                selectedSiteId = siteId;
                                selectedSiteDoc=sites.firstWhere((site)=>site.id==siteId);
                                selectedBatimentId=null;
                                selectedBatimentDoc=null;

                              });
                            },
                          );
                        },
                      ),
                    if (type == 'salle' && selectedSiteId != null)
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('sites')
                            .doc(selectedSiteId)
                            .collection('batiments')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const CircularProgressIndicator();
                          final batiments = snapshot.data!.docs;
                          return DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Bâtiment Parent'),
                            items: batiments.map((batiment) {
                              return DropdownMenuItem<String>(
                                value: batiment.id,
                                child: Text(batiment['nom']),
                              );
                            }).toList(),
                            onChanged: (String? batimentId) {
                              setState(() {
                                selectedBatimentId = batimentId;
                                selectedBatimentDoc = batiments.firstWhere((batiment) => batiment.id == batimentId);
                              });
                            },
                            value: selectedBatimentId ,
                          );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _addData(type, nomController.text, adresseController.text, selectedSiteId, selectedBatimentId);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Ajouter'),
                ),
              ],
            );
          },
        );
      },
    );
  }*/
  void _showAddDialog(String type) {
  final TextEditingController nomController = TextEditingController();
  final TextEditingController adresseController = TextEditingController();

  showDialog(
    context: context,
    builder: (BuildContext context) {
      String? selectedSiteId;
      String? selectedBatimentId;

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Ajouter un $type'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomController,
                    decoration: InputDecoration(labelText: 'Nom du $type *'),
                  ),
                  TextField(
                    controller: adresseController,
                    decoration: InputDecoration(labelText: 'Adresse du $type'),
                  ),
                  
                  // Dropdown pour sélectionner le site (pour bâtiment et salle)
                  if (type == 'batiment' || type == 'salle')
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore.collection('sites').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final sites = snapshot.data!.docs;
                        
                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Site Parent *'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Sélectionnez un site'),
                                ),
                                ...sites.map((site) {
                                  return DropdownMenuItem<String>(
                                    value: site.id,
                                    child: Text(site['nom'] ?? 'Sans nom'),
                                  );
                                }).toList(),
                              ],
                              onChanged: (String? siteId) {
                                setState(() {
                                  selectedSiteId = siteId;
                                  selectedBatimentId = null; // Réinitialiser le bâtiment quand le site change
                                });
                              },
                              value: selectedSiteId,
                              validator: (value) {
                                if ((type == 'batiment' || type == 'salle') && value == null) {
                                  return 'Veuillez sélectionner un site';
                                }
                                return null;
                              },
                            ),
                            if (selectedSiteId == null && (type == 'batiment' || type == 'salle'))
                              const Text(
                                'Veuillez sélectionner un site',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                          ],
                        );
                      },
                    ),

                  // Dropdown pour sélectionner le bâtiment (uniquement pour les salles)
                  if (type == 'salle' && selectedSiteId != null)
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('sites')
                          .doc(selectedSiteId)
                          .collection('batiments')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final batiments = snapshot.data!.docs;
                        
                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Bâtiment Parent *'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Sélectionnez un bâtiment'),
                                ),
                                ...batiments.map((batiment) {
                                  return DropdownMenuItem<String>(
                                    value: batiment.id,
                                    child: Text(batiment['nom'] ?? 'Sans nom'),
                                  );
                                }).toList(),
                              ],
                              onChanged: (String? batimentId) {
                                setState(() {
                                  selectedBatimentId = batimentId;
                                });
                              },
                              value: selectedBatimentId,
                              validator: (value) {
                                if (type == 'salle' && value == null) {
                                  return 'Veuillez sélectionner un bâtiment';
                                }
                                return null;
                              },
                            ),
                            if (selectedBatimentId == null && type == 'salle')
                              const Text(
                                'Veuillez sélectionner un bâtiment',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Validation manuelle
                  bool isValid = true;
                  String errorMessage = '';

                  if (nomController.text.isEmpty) {
                    isValid = false;
                    errorMessage = 'Le nom est requis';
                  }
                  else if ((type == 'batiment' || type == 'salle') && selectedSiteId == null) {
                    isValid = false;
                    errorMessage = 'Veuillez sélectionner un site parent';
                  }
                  else if (type == 'salle' && selectedBatimentId == null) {
                    isValid = false;
                    errorMessage = 'Veuillez sélectionner un bâtiment parent';
                  }

                  if (!isValid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(errorMessage),
                    ));
                    return;
                  }

                  // Si tout est valide, procéder à l'ajout
                  try {
                    if (type == 'site') {
                      await _firestore.collection('sites').add({
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                    else if (type == 'batiment' && selectedSiteId != null) {
                      await _firestore
                          .collection('sites')
                          .doc(selectedSiteId)
                          .collection('batiments')
                          .add({
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }
                    else if (type == 'salle' && selectedSiteId != null && selectedBatimentId != null) {
                      await _firestore
                          .collection('sites')
                          .doc(selectedSiteId)
                          .collection('batiments')
                          .doc(selectedBatimentId)
                          .collection('salle')
                          .add({
                        'nom': nomController.text,
                        'adresse': adresseController.text,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$type ajouté avec succès')),
                    );
                    
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $e')),
                    );
                  }
                },
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      );
    },
  );
}

  // Fonction pour ajouter les données à Firestore
  Future<void> _addData(String type, String nom, String adresse, String? siteId, String? batimentId) async {
    if (nom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom est requis')),
      );
      return;
    }

    final data = {
      'nom': nom,
      'adresse': adresse,
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      if (type == 'site') {
        await _firestore.collection('sites').add(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Site ajouté avec succès')),
        );
      } else if (type == 'batiment' && siteId != null) {
        await _firestore
            .collection('sites')
            .doc(siteId)
            .collection('batiments')
            .add(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bâtiment ajouté avec succès')),
        );
      } else if (type == 'salle' && batimentId != null && siteId != null) {
        await _firestore
            .collection('sites')
            .doc(siteId)
            .collection('batiments')
            .doc(batimentId)
            .collection('salle')
            .add(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salle ajoutée avec succès')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez un parent valide')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'ajout : $e')),
      );
    }
  }
}