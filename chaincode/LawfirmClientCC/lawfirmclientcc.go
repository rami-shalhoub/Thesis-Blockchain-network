package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-protos-go/peer"
	"github.com/hyperledger/fabric-protos-go/msp"
	"github.com/golang/protobuf/proto"
)

// LawFirmContract implements the smart contract
type LawFirmContract struct{}

// Document represents legal documents
type Document struct {
	DocID        string            `json:"docID"`
	DocType      string            `json:"docType,omitempty"`
	Timestamp    string            `json:"timestamp"`
	Parties      []string          `json:"parties"`
	Status       string            `json:"status"` // draft, review, executed, archived
	Signatures   map[string]string `json:"signatures"`
	MetadataHash string            `json:"metadataHash"`
	CustomFields map[string]string `json:"customFields,omitempty"`
}

// Init is called during chaincode instantiation
func (lc *LawFirmContract) Init(stub shim.ChaincodeStubInterface) peer.Response {
	return shim.Success(nil)
}

// Invoke contains all the chaincode functions
func (lc *LawFirmContract) Invoke(stub shim.ChaincodeStubInterface) peer.Response {
	function, args := stub.GetFunctionAndParameters()
	
	switch function {
	case "CreateDocument":
		if len(args) != 3 {
			return shim.Error("Incorrect number of arguments. Expecting 3 (docID, docType, metadataHash)")
		}
		return lc.createDocument(stub, args[0], args[1], args[2])
	case "AddSignature":
		if len(args) != 2 {
			return shim.Error("Incorrect number of arguments. Expecting 2 (docID, signature)")
		}
		return lc.addSignature(stub, args[0], args[1])
	case "GetDocument":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1 (docID)")
		}
		return lc.getDocument(stub, args[0])
	case "QueryDocumentsByParty":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1 (mspID)")
		}
		return lc.queryDocumentsByParty(stub, args[0])
	case "QueryDocumentsByStatus":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1 (status)")
		}
		return lc.queryDocumentsByStatus(stub, args[0])
	default:
		return shim.Error("Invalid function name")
	}
}

// createDocument creates a new legal document (either party)
func (lc *LawFirmContract) createDocument(stub shim.ChaincodeStubInterface, docID string, docType string, metadataHash string) peer.Response {
	// Get client MSP ID
	mspID, err := getClientMSPID(stub)
	if err != nil {
		return shim.Error(err.Error())
	}

	// Verify only LawFirm or Client orgs can create
	if mspID != "LawFirmOrgMSP" && mspID != "ClientOrgMSP" {
		return shim.Error("only LawFirmOrg or ClientOrg can create documents")
	}

	exists, err := lc.documentExists(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}
	if exists {
		return shim.Error(fmt.Sprintf("document %s already exists", docID))
	}

	doc := Document{
		DocID:        docID,
		DocType:      docType,
		Timestamp:    time.Now().UTC().Format(time.RFC3339),
		Parties:      []string{"LawFirmOrgMSP", "ClientOrgMSP"},
		Status:       "draft",
		Signatures:   make(map[string]string),
		MetadataHash: metadataHash,
		CustomFields: make(map[string]string),
	}

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return shim.Error(err.Error())
	}

	if err := stub.PutState(docID, docJSON); err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// addSignature adds a signature to the document
func (lc *LawFirmContract) addSignature(stub shim.ChaincodeStubInterface, docID string, signature string) peer.Response {
	// Get client MSP ID
	mspID, err := getClientMSPID(stub)
	if err != nil {
		return shim.Error(err.Error())
	}

	doc, err := lc.getDocumentHelper(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}

	// Verify client is one of the parties
	if mspID != "LawFirmOrgMSP" && mspID != "ClientOrgMSP" {
		return shim.Error("unauthorized party")
	}

	doc.Signatures[mspID] = signature

	// If both parties have signed, mark as executed
	if len(doc.Signatures) == 2 {
		doc.Status = "executed"
		if err := stub.SetEvent("DocumentExecuted", []byte(docID)); err != nil {
			return shim.Error(err.Error())
		}
	}

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return shim.Error(err.Error())
	}

	if err := stub.PutState(docID, docJSON); err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// Helper function to get client MSP ID
func getClientMSPID(stub shim.ChaincodeStubInterface) (string, error) {
	creator, err := stub.GetCreator()
	if err != nil {
		return "", fmt.Errorf("failed to get creator: %v", err)
	}

	// Unmarshal the SerializedIdentity protobuf
	sid := &msp.SerializedIdentity{}
	if err := proto.Unmarshal(creator, sid); err != nil {
		return "", fmt.Errorf("failed to unmarshal creator identity: %v", err)
	}

	return sid.Mspid, nil
}

// getDocument returns the document with given ID
func (lc *LawFirmContract) getDocument(stub shim.ChaincodeStubInterface, docID string) peer.Response {
	doc, err := lc.getDocumentHelper(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(docJSON)
}

// Helper function for getDocument
func (lc *LawFirmContract) getDocumentHelper(stub shim.ChaincodeStubInterface, docID string) (*Document, error) {
	docJSON, err := stub.GetState(docID)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if docJSON == nil {
		return nil, fmt.Errorf("document %s does not exist", docID)
	}

	var doc Document
	if err := json.Unmarshal(docJSON, &doc); err != nil {
		return nil, err
	}

	return &doc, nil
}

// documentExists checks if document exists
func (lc *LawFirmContract) documentExists(stub shim.ChaincodeStubInterface, docID string) (bool, error) {
	docJSON, err := stub.GetState(docID)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}
	return docJSON != nil, nil
}

// queryDocumentsByParty returns all documents involving the specified party
func (lc *LawFirmContract) queryDocumentsByParty(stub shim.ChaincodeStubInterface, mspID string) peer.Response {
	queryString := fmt.Sprintf(`{"selector":{"parties":"%s"}}`, mspID)
	
	resultsIterator, err := stub.GetQueryResult(queryString)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	var documents []*Document
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}

		var doc Document
		if err := json.Unmarshal(queryResponse.Value, &doc); err != nil {
			return shim.Error(err.Error())
		}
		documents = append(documents, &doc)
	}

	documentsJSON, err := json.Marshal(documents)
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(documentsJSON)
}

// queryDocumentsByStatus returns all documents with given status
func (lc *LawFirmContract) queryDocumentsByStatus(stub shim.ChaincodeStubInterface, status string) peer.Response {
	queryString := fmt.Sprintf(`{"selector":{"status":"%s"}}`, status)
	
	resultsIterator, err := stub.GetQueryResult(queryString)
	if err != nil {
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	var documents []*Document
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}

		var doc Document
		if err := json.Unmarshal(queryResponse.Value, &doc); err != nil {
			return shim.Error(err.Error())
		}
		documents = append(documents, &doc)
	}

	documentsJSON, err := json.Marshal(documents)
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(documentsJSON)
}

func main() {
	server := &shim.ChaincodeServer{
		CCID:    os.Getenv("CHAINCODE_CCID"),
		Address: os.Getenv("CHAINCODE_ADDRESS"),
		CC:      new(LawFirmContract),
		TLSProps: shim.TLSProperties{
			Disabled: true, // Set to false for production with proper certs
		},
	}

	// Start the chaincode external server
	if err := server.Start(); err != nil {
		log.Printf("Error starting LawFirm chaincode: %s", err)
	}
}