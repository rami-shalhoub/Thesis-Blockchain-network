package main

import (
	"encoding/json"
	"fmt"
	"log"
	"time"
	"os"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-protos-go/peer"
	"github.com/hyperledger/fabric-protos-go/msp"
	"github.com/golang/protobuf/proto"
)

// RetailContract implements the smart contract
type RetailContract struct{}

// Document represents the structure stored in the ledger
type Document struct {
	DocID           string            `json:"docID"` // IPFS hash
	DocType         string            `json:"docType,omitempty"`
	Timestamp       string            `json:"timestamp"`
	Owner           string            `json:"owner"`
	Status          string            `json:"status"` // pending, approved, rejected
	ClientSignature string            `json:"clientSignature,omitempty"`
	MetadataHash    string            `json:"metadataHash"`
	CustomFields    map[string]string `json:"customFields,omitempty"`
}

// Init is called during chaincode instantiation
func (rc *RetailContract) Init(stub shim.ChaincodeStubInterface) peer.Response {
	return shim.Success(nil)
}

// Invoke contains all the chaincode functions
func (rc *RetailContract) Invoke(stub shim.ChaincodeStubInterface) peer.Response {
	function, args := stub.GetFunctionAndParameters()
	
	switch function {
	case "CreateDocument":
		if len(args) != 3 {
			return shim.Error("Incorrect number of arguments. Expecting 3")
		}
		return rc.createDocument(stub, args[0], args[1], args[2])
	case "ApproveDocument":
		if len(args) != 2 {
			return shim.Error("Incorrect number of arguments. Expecting 2")
		}
		return rc.approveDocument(stub, args[0], args[1])
	case "RejectDocument":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1")
		}
		return rc.rejectDocument(stub, args[0])
	case "GetDocument":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1")
		}
		return rc.getDocument(stub, args[0])
	case "QueryDocumentsByStatus":
		if len(args) != 1 {
			return shim.Error("Incorrect number of arguments. Expecting 1")
		}
		return rc.queryDocumentsByStatus(stub, args[0])
	default:
		return shim.Error("Invalid function name")
	}
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

// createDocument creates a new document (RetailOrg only)
func (rc *RetailContract) createDocument(stub shim.ChaincodeStubInterface, docID string, docType string, metadataHash string) peer.Response {
	// Get client MSP ID
	mspID, err := getClientMSPID(stub)
	if err != nil {
		return shim.Error(fmt.Sprintf("failed to get MSP ID: %v", err))
	}

	// Verify only RetailOrg can create documents
	if mspID != "RetailOrgMSP" {
		return shim.Error("only RetailOrg can create documents")
	}

	// Check if document already exists
	exists, err := rc.documentExists(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}
	if exists {
		return shim.Error(fmt.Sprintf("document %s already exists", docID))
	}

	// Create new document
	doc := Document{
		DocID:        docID,
		DocType:      docType,
		Timestamp:    time.Now().UTC().Format(time.RFC3339),
		Owner:        mspID,
		Status:       "pending",
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

// approveDocument approves a document (ClientOrg only)
func (rc *RetailContract) approveDocument(stub shim.ChaincodeStubInterface, docID string, clientSignature string) peer.Response {
	// Get client MSP ID
	mspID, err := getClientMSPID(stub)
	if err != nil {
		return shim.Error(fmt.Sprintf("failed to get MSP ID: %v", err))
	}

	// Verify only ClientOrg can approve
	if mspID != "ClientOrgMSP" {
		return shim.Error("only ClientOrg can approve documents")
	}

	// Get the document
	doc, err := rc.getDocumentHelper(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}

	// Check document status
	if doc.Status != "pending" {
		return shim.Error(fmt.Sprintf("document %s is not pending approval", docID))
	}

	// Update document
	doc.ClientSignature = clientSignature
	doc.Status = "approved"

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return shim.Error(err.Error())
	}

	if err := stub.PutState(docID, docJSON); err != nil {
		return shim.Error(err.Error())
	}

	// Emit approval event
	if err := stub.SetEvent("DocumentApproved", []byte(docID)); err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// rejectDocument rejects a document (ClientOrg only)
func (rc *RetailContract) rejectDocument(stub shim.ChaincodeStubInterface, docID string) peer.Response {
	// Get client MSP ID
	mspID, err := getClientMSPID(stub)
	if err != nil {
		return shim.Error(fmt.Sprintf("failed to get MSP ID: %v", err))
	}

	// Verify only ClientOrg can reject
	if mspID != "ClientOrgMSP" {
		return shim.Error("only ClientOrg can reject documents")
	}

	// Get the document
	doc, err := rc.getDocumentHelper(stub, docID)
	if err != nil {
		return shim.Error(err.Error())
	}

	// Check document status
	if doc.Status != "pending" {
		return shim.Error(fmt.Sprintf("document %s is not pending approval", docID))
	}

	// Update document
	doc.Status = "rejected"

	docJSON, err := json.Marshal(doc)
	if err != nil {
		return shim.Error(err.Error())
	}

	if err := stub.PutState(docID, docJSON); err != nil {
		return shim.Error(err.Error())
	}

	// Emit rejection event
	if err := stub.SetEvent("DocumentRejected", []byte(docID)); err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

// getDocument returns the document with given ID
func (rc *RetailContract) getDocument(stub shim.ChaincodeStubInterface, docID string) peer.Response {
	doc, err := rc.getDocumentHelper(stub, docID)
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
func (rc *RetailContract) getDocumentHelper(stub shim.ChaincodeStubInterface, docID string) (*Document, error) {
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
func (rc *RetailContract) documentExists(stub shim.ChaincodeStubInterface, docID string) (bool, error) {
	docJSON, err := stub.GetState(docID)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}
	return docJSON != nil, nil
}

// queryDocumentsByStatus returns all documents with given status
func (rc *RetailContract) queryDocumentsByStatus(stub shim.ChaincodeStubInterface, status string) peer.Response {
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
		CC:      new(RetailContract),
		TLSProps: shim.TLSProperties{
			Disabled: true, // Set to false for production with proper certs
		},
	}

	// Start the chaincode external server
	if err := server.Start(); err != nil {
		log.Printf("Error starting Retail chaincode: %s", err)
	}
}
