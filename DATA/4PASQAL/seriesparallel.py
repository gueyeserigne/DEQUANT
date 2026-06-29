# -*- coding: utf-8 -*-
###########################################
# Auteur : Serigne A. Gueye
# Réalisé au LIA Année académique 2023-2024
# Pour le Projet PASQAL
# version v1
# Méthode pour la génération automatique de graphes series-parallel
# Création : 01 Avril 2024
# Dernière mise à jour : 01 Avril 2024
###########################################
import networkx as nx
import matplotlib.pyplot as plt
import random as rd
#from random import sample

########################################"
# Création de k arêtes
########################################"
def Q(k):
	R = []
	for i in range(0,k):
		o = 2*i
		d = 2*i+1
		#G = nx.MultiDiGraph(s=o,t=d)
		G = nx.Graph(s=o,t=d)
		G.add_edge(o,d,weight=rd.randrange(1,100))
		R.append(G)
	return(R)

######################################################
# Construction d'un graphe R obtenu en mettant en série 
# les graphes G et H
######################################################
def series(G,H):
	#print("Series")
	#print("G")
	#print(list(G.edges))
	#print("Source  = ", G.graph['s'])
	#print("Puit  = ", G.graph['t'])
	#print("H")
	#print(list(H.edges))
	#print("Source  = ", H.graph['s'])
	#print("Puit  = ", H.graph['t'])
	#print("*****************")
	R = nx.union(G,H)
	R = nx.contracted_nodes(R,G.graph['t'],H.graph['s'])
	R.graph['s']=G.graph['s']
	R.graph['t']=H.graph['t']
	#print("R")
	#print(list(R.edges))
	#print("*****************")
	return(R)

######################################################
# Construction d'un graphe R obtenu en mettant en parallèle
# les graphes G et H
######################################################
def parallel(G,H):
	#print("Parallel")
	#print("G")
	#print(list(G.edges))
	#print("Source  = ", G.graph['s'])
	#print("Puit  = ", G.graph['t'])
	#print("H")
	#print(list(H.edges))
	#print("Source  = ", H.graph['s'])
	#print("Puit  = ", H.graph['t'])
	#print("*****************")
	R = nx.union(G,H)
	R = nx.contracted_nodes(R,G.graph['s'],H.graph['s'])
	R = nx.contracted_nodes(R,G.graph['t'],H.graph['t'])
	R.graph['s']=G.graph['s']
	R.graph['t']=G.graph['t']

	#print("R")
	#print(list(R.edges))
	#print("*****************")

	return(R)

def seriesparallel(max):
	#k = rd.randrange(2,max)
	k = 20
	L = Q(k)
	#for i in range(0,len(L)):
	#	print(L[i].edges)

	while(len(L) > 1):
		G = rd.sample(L,2)
		p = rd.sample([True,False],1) 
		#print(p)
		if(p[0] == True):
			R = series(G[0],G[1])
		else:
			R = parallel(G[0],G[1])
		L.remove(G[0])
		L.remove(G[1])
		L.append(R)
	return(L)


def main(n,max):
	rep = "LIA-INSTANCES/SERIESPARALLEL/"
	nom = "spg"

	for i in range(0,n):
		G = seriesparallel(max)
		if((G[0].number_of_nodes() >= 8) and (G[0].number_of_nodes() <= 12)):
		    fic = rep+nom+"_"+str(i)+"_"+str(G[0].number_of_nodes())
		    for i in list(G[0].nodes):
			    #G[0].add_edge(i,i,weight=rd.randrange(-100,100))
			    G[0].add_edge(i,i,weight=rd.randrange(-100,-1))
		    nx.write_weighted_edgelist(G[0],fic)
		#nx.draw_planar(G[0], with_labels=True)
		#plt.show()





main(30,20)
#print(G)
#print(list(G[0].nodes))
#print("Source = ", G[0].graph['s'])
#print("Puit = ", G[0].graph['t'])
#nx.draw_planar(G[0], with_labels=True)
#plt.show()
#print(list(G[0].edges))

