"""Turtle -> RDF/XML -> HermiT consistency check. Usage: hermit_check.py file.ttl..."""
import sys, tempfile, os
import rdflib
from owlready2 import World, sync_reasoner_hermit, OwlReadyInconsistentOntologyError

for path in sys.argv[1:]:
    graph = rdflib.Graph(); graph.parse(path, format="turtle")
    xml = os.path.join(tempfile.mkdtemp(), "o.owl")
    graph.serialize(xml, format="xml")
    world = World(); onto = world.get_ontology("file://" + xml).load()
    try:
        with onto:
            sync_reasoner_hermit(world, infer_property_values=False, debug=0)
        bad = list(world.inconsistent_classes())
        print(os.path.basename(path), "triples", len(graph), "classes", len(list(onto.classes())),
              "individuals", len(list(onto.individuals())), "CONSISTENT", "unsatisfiable:", bad)
    except OwlReadyInconsistentOntologyError:
        print(os.path.basename(path), "INCONSISTENT")
