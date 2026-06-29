# -*- coding: utf-8 -*-
###########################################
# Auteur : Serigne A. Gueye
# Réalisé au LIA Année académique 2023-2024
# Pour le Projet PASQAL
# version v1
# Création : 20 Mars 2024
# Dernière mise à jour : 20 Mars 2024
###########################################
import networkx as nx
import matplotlib.pyplot as plt

###########################################
# Descriptif : Création d'un graph networkx
# à partir d'un fichier ORLIB
###########################################
# Entrée : 
# - nom : nom d'un fichier texte contenant
# un graphe
###########################################
# Sortie : 
# - G : graph networkx
###########################################
def graph_orlib(nom):
	fichier = open(nom,'r')
	G = nx.Graph()
	liste  = fichier.readlines()
	listesplit = [x.split() for x in liste]
	listeint = [[int(y) for y in x] for x in listesplit]
	for i in range(1,len(listeint)):
		#print(listeint[i])
		G.add_edge(listeint[i][0],listeint[i][1],weight=listeint[i][2])

	fichier.close()

	list(G.nodes)
	list(G.edges)
	return G

def graph_orlib_pos(nom):
	fichier = open(nom,'r')
	G = nx.Graph()
	liste  = fichier.readlines()
	listesplit = [x.split() for x in liste]
	listeint = [[int(y) for y in x] for x in listesplit]
	for i in range(1,len(listeint)):
		#print(listeint[i])
		if(listeint[i][2] >= 0):
			G.add_edge(listeint[i][0],listeint[i][1],weight=listeint[i][2])

	fichier.close()

	list(G.nodes)
	list(G.edges)
	return G



def graph_qplib(nom):
	fichier = open(nom,'r')
	G = nx.Graph()
	liste  = fichier.readlines()
	listesplit = [x.split() for x in liste]
	listeint = [[int(y) for y in x] for x in listesplit]
	for i in range(1,listeint[0][1]+1):
		#print(listeint[i])
		G.add_edge(listeint[i][0],listeint[i][1],weight=listeint[i][2])

	fichier.close()

	list(G.nodes)
	list(G.edges)
	return G


def graph_qplib_pos(nom):
	fichier = open(nom,'r')
	G = nx.Graph()
	liste  = fichier.readlines()
	listesplit = [x.split() for x in liste]
	listeint = [[int(y) for y in x] for x in listesplit]
	for i in range(1,listeint[0][1]+1):
		#print(listeint[i])
		if(listeint[i][2] >= 0):
			G.add_edge(listeint[i][0],listeint[i][1],weight=listeint[i][2])

	fichier.close()

	list(G.nodes)
	list(G.edges)
	return G



###########################################
# Descriptif : Détermination des composantes connexes de G
###########################################
# Entrée : 
# - G : graph networkx
###########################################
# Sortie : 
# - liste des graphes networkx composante connexe
###########################################
def composantes_connexes(G):
	return([G.subgraph(c).copy() for c in nx.connected_components(G)])


###########################################
# Descriptif : Décomposition d'un graphe G
###########################################
# Entrée : 
# - G : graph networkx
###########################################
# Sortie : 
# - L : liste des sommets formant l'ensemble d'articulation
###########################################
def decomposition(G,seuil):
	# Si le nombre de noeuds de G est inférieure à un seuil (12) 
	# on le rajoute à la liste des sous-graphes identifiées de la décomposition
	if(len(list(G.nodes)) <= seuil):
		SG.append(G)
	else:
		# Sinon on détermine d'abord les composantes connexes de G
		C = composantes_connexes(G)	
		# Pour chaque composante connexe c
		for c in C:
			# Si le nombre de noeuds de c est au moins 2
			if(len(list(c.nodes)) >= seuil):
				# On recherche le meilleur ensemble d'articulation (node_cut)
				print("# noeuds = ", len(list(c.nodes)))
				print("# aretes = ", len(list(c.edges)))				
				node_cut = meilleur_ensemble_articulation(c)
				print("Meilleur_ensemble_articulation",node_cut)
				# Chaque noeud de node_cut est ajouté à la liste PA des points d'articulations
				for v in node_cut:
					PA.append(v)
				# On élimine de G les noeuds de cet ensemble d'articulation.
				c.remove_nodes_from(node_cut)
				# La suppresion précédente de noeuds donnent des composantes connexes 
				# que l'on récupère dans cc
				cc = composantes_connexes(c)
				# Pour chaque composante connexe,in relance récursivement la décomposition
				for d in cc:
					#	R.append(d)
					decomposition(d,seuil)

def my_all_node_cuts(G):

	sommets = list(G.nodes)
	for i in range(0,len(sommets)):
		for j in range(i+1,len(sommets)):
			#print("Sommets ",sommets[i]," ",sommets[j])
			# On fait une copie de G dans H
			H = G.copy()
			# On retire les noeuds se trouvant dans e
			H.remove_node(sommets[i])
			H.remove_node(sommets[j])
			if(nx.is_connected(H) == False):
				# On détermine les composantes connexes induits par cette suppression
				C = composantes_connexes(H)
				# On crée une liste des tailles (nombre de noeuds) de ces composantes
				L = [len(list(x.nodes)) for x in C]
				# On calcule l'écart moyen des tailles
				moy = ecart_moyen(L)
				# Si cet écart est inférieur à la plus petite valeur trouvée jusque là,
				# on met à jour R
				print("Points articulation",sommets[i]," ",sommets[j])
				print("Moy = ",moy)



###########################################
# Descriptif : Détermination du meilleur ensemble d'articulation
# dont la suppression permet de couper le graphe en 
# deux parties de taille proche
###########################################
# Entrée : 
# - G : graph networkx
###########################################
# Sortie : 
# - R : ensemble d'articulation
###########################################

def meilleur_ensemble_articulation(G):
	# E contient tous les ensembles d'articulation de taille minimale possible
	#print("Fonction Meilleur Ensemble Articulation")
	#k = nx.node_connectivity(G)
	#print("node_connectivity = ",k)
	E = list(nx.all_node_cuts(G))
	#E = []
	#E.append(nx.minimum_node_cut(G))
	print("E = ",E)
	mini = 1e+5
	R = E[0]
	# Pour chaque élément e de E 
	for e in E:
		# On fait une copie de G dans H
		H = G.copy()
		# On retire les noeuds se trouvant dans e
		H.remove_nodes_from(e)
		# On détermine les composantes connexes induits par cette suppression
		C = composantes_connexes(H)
		moy = 1e+5
		if(len(C) >= 2):
			# On crée une liste des tailles (nombre de noeuds) de ces composantes
			L = [len(list(x.nodes)) for x in C]
			# On calcule l'écart moyen des tailles
			moy = ecart_moyen(L)
		# Si cet écart est inférieur à la plus petite valeur trouvée jusque là,
		# on met à jour R
		if(moy < mini):
			mini = moy
			R = e
	# On retourne le meilleur ensemble d'articulation
	return(R)

###########################################
# Descriptif : Calcul de la moyenne des
# différences absolues entre couples d'élements d'une liste d'entiers.
###########################################
# Entrée : 
# - L : liste d'entiers
###########################################
# Sortie : 
# - R : Moyenne des écarts
###########################################		
def ecart_moyen(L):
	print("L = ",L)
	S = 0
	for i in L:
		for j in L:
			S = S + abs(i-j)

	n = len(L)
	m = n*(n-1)
	return(S/m)

def main(fichier,letype):
	repentree = "../"+letype+"/"
	repsortiegraphs = "FROM"+letype+"/GRAPHS/"
	repsortieart = "FROM"+letype+"/ART/"
	art = "art_"
	ssnom = "_SG"

	fichier = open(fichier,'r')
	liste  = fichier.readlines()
	print("Fichier"+"\t"+"Sous_Graphes"+"\t"+"Taille(SG)"+"\t"+"Taille(PA)"+"\n")
	for nom in liste:
		SG.clear()
		PA.clear()
		nom = nom.strip() 
		#G = graph_orlib(repentree+nom.strip())
		#G = graph_qplib(repentree+nom.strip())
		G = graph_qplib_pos(repentree+nom.strip())
		decomposition(G,12)
		i = 0
		for g in SG:
			fic = repsortiegraphs+nom+ssnom+"_"+str(i)
			#print(fic)
			#print(list(g.nodes))
			#print(list(g.edges))
			if(len(list(g.nodes)) > 1):
				nx.write_weighted_edgelist(g,fic)
				i = i+1



		#print("Points d'articulation : ",PA)
		writer = open(repsortieart+art+nom+ssnom, 'w')
		for a in PA:
			writer.write(str(a)+" ")
		writer.close()
		print(nom+"\t"+str(i)+"\t"+str(len(SG))+"\t"+str(len(PA))+"\n")

		


##########################################################################
# 			TESTS
##########################################################################
global SG # Liste des sous-graphes
global PA # Liste des points d'articulation

SG = []
PA = []

fichier = "listqplib"
#main(fichier,"QPLIB")

# Test de la fonction graph(nom)
#nom = "bqpgka50_1.txt"
G = graph_qplib_pos("../QPLIB/QPLIB.3565.qplib")
#my_all_node_cuts(G)
#nx.draw_spring(G, with_labels=True)
nx.draw(G)
#nx.draw_spectral(G)
#G = nx.path_graph(5)
#R = meilleur_ensemble_articulation(G)
#print(R)
plt.show()
