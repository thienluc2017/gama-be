/**
* Name: Verify2020
* Based on the internal empty template. 
* Author: HuyNQ52
* Tags: Add simulation step and verify
*/


model Verify2020

/* Insert your model definition here */

global {
//	list<int> cNbFarms <- [5499, 1989, 394];		// 5499 Small farms; 1989 Medium farms; 394 Large farms
	list<int> cNbFarms <- [700, 250, 50];
	float cTPDirect <- 0.6; 						// Transmission probability of direct contact
	list<float> cTPIndirect <- [0.6, 0.6, 0.006];	// TP of indirect contact: Small/Medium farms - 0.6; Large farms - 0.006	
	list<int> cDuration <- [52, 52, 4];				// Infectious duration for: Small farm - 52 weeks; Medium farm - 10-12 weeks; Large farm - 4 weeks
	
	
	matrix vCRDirect 	<- matrix([[0.072, 0, 0], [0.072, 0.073, 0], [0, 0.073, 0]]); // Mean direct contact rate/week. vCRDirect[2,1] - Mean direct contact rate of Large farm to Medium farm = 0.073
	matrix vCRIndirect 	<- matrix([[0.282, 0.282, 0], [0.282, 0.271, 3.5], [0, 0.271, 3.5]]); // Mean indirect contact rate/week. vCRIndirect[2,1] - Mean indirect contact rate of Large farm to Medium farm = 0.271
	
	bool pEnDirect <- true;
	bool pEnLarge <- true;
	float pKTPIndirect <- 1.0; 	// Indirect TP change - New indirect TP = vKIndirect * old indirect TP
	float pKMove <- 1.0;		// Movement control rate - 1: No movement restriction; 0: Movement restriction 100%	
	int pMoveRTime <- 4;		// Movement restriction within 4 weeks of detection of outbreaks 
	// int vCullTime <- 53;		// Culling within 53 weeks of detection of outbreaks. It mean no culling in the simulation time
	int pDays <- 7; 		// Number of days per 1 simulation step

	int vNbContacts <- 0;
	map vNbInfectedFarms <- [0::0, 1::1, 2::0];

	matrix verifyCRDirect 	<- matrix([[0.0, 0, 0], [0.0, 0.0, 0], [0, 0.0, 0]]);
	matrix verifyCRIndirect <- matrix([[0.0, 0.0, 0], [0.0, 0.0, 0.0], [0, 0.0, 0.0]]);
	int verifyDirectContacts <- 0;
	int verifyIndirectContacts <- 0;
	int verifyNbContacts <- 0;

	init {
		/* Initialize farms */
		create sFarm number: cNbFarms[1] {
			aType <- 1;
		}
		one_of(sFarm).isInfected <- true;
		create sFarm number: cNbFarms[0] {
			aType <- 0;
		}
		create sFarm number: cNbFarms[2] {
			aType <- 2;
		}
		save ("Verify") to: "../includes/verify.txt" type: "text" rewrite: true;
	}
	
	reflex rInfo when: cycle > 0 and mod(cycle,int(cDuration[0] * 7/pDays /2)) = 0 {
		write "Cycle: " + cycle + " - vNbInfectedFarms: " + vNbInfectedFarms;
	}
	reflex rPause when: cycle = 52 { 
		ask sFarm {
			if aInfectedDays > pMoveRTime {
				save ("[MR]: " + name + " - aIndirectNew: " + aIndirectNew) to: "../includes/verify.txt" type: "text" rewrite: false;
			} 
		}
		write "Pause"; 
		do pause;
	}

	reflex rParseParams when: cycle = 0 {
		if !pEnDirect {
			write "Disable Direct contacts";
			vCRDirect 	<- matrix([[0.0, 0, 0], [0.0, 0.0, 0], [0, 0.0, 0]]);
		}
		if !pEnLarge {
			write "Disable contacts of Large farms";
			vCRDirect 	<- matrix([[0.072, 0, 0], [0.072, 0.073, 0], [0, 0.0, 0]]);
			vCRIndirect <- matrix([[0.282, 0.282, 0], [0.282, 0.271, 0], [0, 0.0, 0.0]]);
		}
	}

	reflex rInitContacts {
		vNbContacts <- 0;
		verifyDirectContacts <- 0;
		verifyIndirectContacts <- 0;
		verifyNbContacts <- 0;
		ask sFarm {
			/* Regenerate number of contacts */
			loop i from: 0 to: 2 {
				if aInfectedDays > pMoveRTime {
					// write " Movement restriction: " + name;
					aNbDirect[i] 	<- poisson(pKMove * vCRDirect[aType, i] * pDays/7);
					aNbIndirect[i] 	<- poisson(pKMove * vCRIndirect[i, aType] * pDays/7);
				} else {
					aNbDirect[i] 	<- poisson(vCRDirect[aType, i] * pDays/7);
					aNbIndirect[i] 	<- poisson(vCRIndirect[i, aType] * pDays/7);
				}
				vNbContacts <- vNbContacts + aNbDirect[i];
				vNbContacts <- vNbContacts + aNbIndirect[i];
				verifyCRDirect[aType, i] <- verifyCRDirect[aType, i] + aNbDirect[i];
				verifyCRIndirect[i, aType] <- verifyCRIndirect[i, aType] + aNbIndirect[i];
			}
		}

		/* Create contacts */
		ask sFarm {
			/* Create direct contacts */
			loop i from: 0 to: 2 {
				loop times: aNbDirect[i] - length(aDirect[i]) {
					loop while: true {
						sFarm vFarm <- one_of(sFarm); // TODO: at_distance cRange
						if vFarm != self and vFarm.aType = i {
							add vFarm to: aDirect[i];
							break;
						}
					}
				}
				verifyNbContacts <- verifyNbContacts + length(aDirect[i]);
			}

			/* Create indirect contacts */
			aIndirectNew 	<- [0::[], 1::[], 2::[]];
			loop i from: 0 to: 2 {
				loop times: aNbIndirect[i] - length(aIndirect[i]) {
					loop while: true {
						sFarm vFarm <- one_of(sFarm); // TODO: at_distance cRange
						if vFarm != self and (vFarm.aType = i) {
							add vFarm to: aIndirect[i];						
							break;
						}
					}
				}
				verifyNbContacts <- verifyNbContacts + length(aIndirect[i]);
			}
		}
		ask sFarm {
			loop i from: 0 to: 2 {
				loop vFarm over: (aNbIndirect[i] among aIndirect[i]) {
					add self to: vFarm.aIndirectNew[aType];
				}
			}
		}
		ask sFarm {
			loop i from: 0 to: 2 {
				verifyIndirectContacts <- verifyIndirectContacts + length(aIndirectNew[i]);
				verifyDirectContacts <- verifyDirectContacts + aNbDirect[i];
			}
		}
		// write "Number of contacts: " + string(vNbContacts) + " " + string(verifyNbContacts) + " = " + string(verifyDirectContacts) + " + " + string(verifyIndirectContacts);
	}
}

species sFarm {
	int aType <- -1; 	// 0 - Small farm; 1 - Medium farm; 2 - Large farm
	bool isInfected <- false;
	int aInfectedDays <- 0;
	map<int,list<sFarm>> aDirect 	<- [0::[], 1::[], 2::[]];
	map<int,list<sFarm>> aIndirect 	<- [0::[], 1::[], 2::[]];
	map<int,list<sFarm>> aIndirectNew <- [0::[], 1::[], 2::[]];
	map<int,int> aNbDirect 			<- [0::0, 1::0, 2::0];
	map<int,int> aNbIndirect 		<- [0::0, 1::0, 2::0];

	reflex rUpdate when: isInfected {
		aInfectedDays <- aInfectedDays + 1;
	}

	reflex rInfect when: isInfected {
		loop i from: 0 to: 2 {
			loop vFarm over: (aNbDirect[i] among aDirect[i]) {
				if not(vFarm.isInfected) {
					if flip(cTPDirect) {
						vFarm.isInfected <- true;
						vNbInfectedFarms[vFarm.aType] <- vNbInfectedFarms[vFarm.aType] + 1;
					}
				}
			}
			loop vFarm over: aIndirectNew[i] {
				if not(vFarm.isInfected) {
					float vTP <- cTPIndirect[vFarm.aType];
					if aInfectedDays > pMoveRTime {
						vTP <- pKMove * vTP;
						// if vTP = 0 {
						// 	write "0 " + name + " -> " + vFarm.name;
						// }
					}
					if flip(vTP) {
						vFarm.isInfected <- true;
						vNbInfectedFarms[vFarm.aType] <- vNbInfectedFarms[vFarm.aType] + 1;
					}
				}
			}
		}
	}
	
}

// experiment eExp type: batch repeat: 16 keep_seed: false until: cycle = cDuration[0] * 7/pDays + 1 {
experiment eExp {
	// reflex rWrite{
	// 	write "End simulation";
	// }
	parameter "Enable Direct contacts: " 	category: "Parameters" var: pEnDirect 	<- true;
	parameter "Enable Large farm contacts: " category: "Parameters" var: pEnLarge 	<- true;
	parameter "Days/Simulation step: " category: "Parameters" var: pDays <- 7 among: [1,2,7];
	parameter "Movement restriction: " category: "Parameters" var: pKMove <- 1.0 min: 0.0 max: 1.0 step: 0.25;
	parameter "Movement restriction timing: " category: "Parameters" var: pMoveRTime <- 4 min: 2 max: 8 step: 2;
	output {
		display myChart refresh: every(1 #cycles) {
			chart "Số trang trại bị nhiễm bệnh" {
				data "Small" value: vNbInfectedFarms[0] color: #red;
				data "Medium" value: vNbInfectedFarms[1] color: #orange;
				data "Large" value: vNbInfectedFarms[2] color: #green;
				data "Total" value: vNbInfectedFarms[0] + vNbInfectedFarms[1] + vNbInfectedFarms[2] color: #black;
			}
		}
	}
}