# -*- coding: utf-8 -*-
###########################################
# Auteur : Serigne A. Gueye
# Réalisé au LIA Année académique 2023-2024
# Pour le Projet PASQAL
# version v1
# Méthode pour la génération automatique de graphes support aléatoires
# avec des termes quadratiques négatifs
# Création : 21 Avril 2024
# Dernière mise à jour : 21 Avril 2024
###########################################
import networkx as nx
import matplotlib.pyplot as plt
import random as rd
#from random import sample

########################################"
# Création de k arêtes
########################################"
def graphe(n,v,d):

	rep = "LIA-INSTANCES/POC/"
	nom = "poc"

	for k in range(0,n):
		G = nx.Graph()
		A = []
		for i in range(1,v+1):
			for j in range(i+1,v+1):
				A.append((i,j))
			
		m = int((d/100)*v*(v-1)/2)
		#print("\n A = ", A)
		for i in range(1,m+1):
			a = rd.sample(A,1)
			#print("\n Sample = ", a)
			G.add_edge(a[0][0],a[0][1],weight=rd.randrange(-100,100))
			A.remove(a[0])
		fic = rep+nom+"_"+str(k)+"_"+str(v)+"_"+str(d)

		for i in list(G.nodes):
			G.add_edge(i,i,weight=rd.randrange(-100,100))


		nx.write_weighted_edgelist(G,fic)



graphe(10,15,10)
graphe(10,15,20)
graphe(10,15,30)
graphe(10,15,40)
graphe(10,15,50)
graphe(10,15,60)
graphe(10,15,70)
graphe(10,15,80)
graphe(10,15,90)
graphe(10,15,100)
