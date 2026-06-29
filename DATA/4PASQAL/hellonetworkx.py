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

G = nx.path_graph(5)
nx.draw(G,with_labels=True, font_weight='bold')
plt.savefig("line_graph_5.png")
